// SPDX-License-Identifier: MIT!!!
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

/* NEONVAULT:
A transfer gate (GatedERC20) for use with NeonVault tokens

It:
    Allows customization of tax and burn rates
    Allows transfer to/from approved Uniswap pools
    Disallows transfer to/from non-approved Uniswap pools
    (doesn't interfere with other crappy AMMs)
    Allows transfer to/from anywhere else
    Allows for free transfers if permission granted
    Allows for unrestricted transfers if permission granted
    Provides a safe and tax-free liquidity adding function
*/

import "./ITransferGate.sol";
import "./Owned.sol";
import "./IUniswapV2Factory.sol";
import "./IERC20.sol";
import "./IUniswapV2Pair.sol";
import "./NeonVault.sol";
import "./Address.sol";
import "./IUniswapV2Router02.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./TokensRecoverable.sol";

struct NeonVaultTransferGateParameters
{
    address dev;
    uint16 stakeRate; // 10000 = 100%
    uint16 burnRate; // 10000 = 100%
    uint16 devRate;  // 10000 = 100%
    address stake;
}

contract NeonVaultTransferGate is Owned, TokensRecoverable, ITransferGate
{   
    using Address for address;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    NeonVaultTransferGateParameters public parameters;
    IUniswapV2Router02 immutable uniswapV2Router;
    IUniswapV2Factory immutable uniswapV2Factory;
    NeonVault immutable neonVault;

    enum AddressState
    {
        Unknown,
        NotPool,
        DisallowedPool,
        AllowedPool
    }

    mapping (address => AddressState) public addressStates;
    IERC20[] public allowedPoolTokens;
    
    bool public unrestricted;
    mapping (address => bool) public unrestrictedControllers;
    mapping (address => bool) public freeParticipant;

    mapping (address => uint256) public liquiditySupply;
    address public mustUpdate;    

    constructor(NeonVault _neonVault, IUniswapV2Router02 _uniswapV2Router)
    {
        neonVault = _neonVault;
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Router.factory());
    }

    function allowedPoolTokensCount() public view returns (uint256) { return allowedPoolTokens.length; }

    function setUnrestrictedController(address unrestrictedController, bool allow) public ownerOnly()
    {
        unrestrictedControllers[unrestrictedController] = allow;
    }

    function setFreeParticipant(address participant, bool free) public ownerOnly()
    {
        freeParticipant[participant] = free;
    }

    function setUnrestricted(bool _unrestricted) public
    {
        require (unrestrictedControllers[msg.sender], "Not an unrestricted controller");
        unrestricted = _unrestricted;
    }

    function setParameters(address _dev, address _stake, uint16 _stakeRate, uint16 _burnRate, uint16 _devRate) public ownerOnly()
    {
        require (_stakeRate <= 10000 && _burnRate <= 10000 && _devRate <= 10000 && _stakeRate + _burnRate + _devRate <= 10000, "> 100%");
        require (_dev != address(0) && _stake != address(0));
        
        NeonVaultTransferGateParameters memory _parameters;
        _parameters.dev = _dev;
        _parameters.stakeRate = _stakeRate;
        _parameters.burnRate = _burnRate;
        _parameters.devRate = _devRate;
        _parameters.stake = _stake;
        parameters = _parameters;
    }

    function allowPool(IERC20 token) public ownerOnly()
    {
        address pool = uniswapV2Factory.getPair(address(neonVault), address(token));
        if (pool == address(0)) {
            pool = uniswapV2Factory.createPair(address(neonVault), address(token));
        }
        AddressState state = addressStates[pool];
        require (state != AddressState.AllowedPool, "Already allowed");
        addressStates[pool] = AddressState.AllowedPool;
        allowedPoolTokens.push(token);
        liquiditySupply[pool] = IERC20(pool).totalSupply();
    }

    function safeAddLiquidity(IERC20 token, uint256 tokenAmount, uint256 neonVaultAmount, uint256 minTokenAmount, uint256 minNeonVaultAmount, address to, uint256 deadline) public
        returns (uint256 neonVaultUsed, uint256 tokenUsed, uint256 liquidity)
    {
        address pool = uniswapV2Factory.getPair(address(neonVault), address(token));
        require (pool != address(0) && addressStates[pool] == AddressState.AllowedPool, "Pool not approved");
        unrestricted = true;

        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        neonVault.transferFrom(msg.sender, address(this), neonVaultAmount);
        neonVault.approve(address(uniswapV2Router), neonVaultAmount);
        token.safeApprove(address(uniswapV2Router), tokenAmount);
        (neonVaultUsed, tokenUsed, liquidity) = uniswapV2Router.addLiquidity(address(neonVault), address(token), neonVaultAmount, tokenAmount, minNeonVaultAmount, minTokenAmount, to, deadline);
        liquiditySupply[pool] = IERC20(pool).totalSupply();
        if (mustUpdate == pool) {
            mustUpdate = address(0);
        }

        if (neonVaultUsed < neonVaultAmount) {
            neonVault.transfer(msg.sender, neonVaultAmount - neonVaultUsed);
        }
        tokenBalance = token.balanceOf(address(this)).sub(tokenBalance); // we do it this way in case there's a burn
        if (tokenBalance > 0) {
            token.safeTransfer(msg.sender, tokenBalance);
        }
        
        unrestricted = false;
    }

    function handleTransfer(address, address from, address to, uint256 amount) external override
        returns (uint256 burn, TransferGateTarget[] memory targets)
    {
        address mustUpdateAddress = mustUpdate;
        if (mustUpdateAddress != address(0)) {
            mustUpdate = address(0);
            liquiditySupply[mustUpdateAddress] = IERC20(mustUpdateAddress).totalSupply();
        }
        AddressState fromState = addressStates[from];
        AddressState toState = addressStates[to];
        if (fromState != AddressState.AllowedPool && toState != AddressState.AllowedPool) {
            if (fromState == AddressState.Unknown) { fromState = detectState(from); }
            if (toState == AddressState.Unknown) { toState = detectState(to); }
            require (unrestricted || (fromState != AddressState.DisallowedPool && toState != AddressState.DisallowedPool), "Pool not approved");
        }
        if (toState == AddressState.AllowedPool) {
            mustUpdate = to;
        }
        if (fromState == AddressState.AllowedPool) {
            if (unrestricted) {
                liquiditySupply[from] = IERC20(from).totalSupply();
            }
            require (IERC20(from).totalSupply() >= liquiditySupply[from], "Cannot remove liquidity");            
        }
        if (unrestricted || freeParticipant[from] || freeParticipant[to]) {
            return (0, new TransferGateTarget[](0));
        }
        NeonVaultTransferGateParameters memory params = parameters;
        // "amount" will never be > totalSupply which is capped at 10k, so these multiplications will never overflow
        burn = amount * params.burnRate / 10000;
        targets = new TransferGateTarget[]((params.devRate > 0 ? 1 : 0) + (params.stakeRate > 0 ? 1 : 0));
        uint256 index = 0;
        if (params.stakeRate > 0) {
            targets[index].destination = params.stake;
            targets[index++].amount = amount * params.stakeRate / 10000;
        }
        if (params.devRate > 0) {
            targets[index].destination = params.dev;
            targets[index].amount = amount * params.devRate / 10000;
        }
    }

    function setAddressState(address a, AddressState state) public ownerOnly()
    {
        addressStates[a] = state;
    }

    function detectState(address a) public returns (AddressState state) 
    {
        state = AddressState.NotPool;
        if (a.isContract()) {
            try this.throwAddressState(a)
            {
                assert(false);
            }
            catch Error(string memory result) {
                // if (bytes(result).length == 1) {
                //     state = AddressState.NotPool;
                // }
                if (bytes(result).length == 2) {
                    state = AddressState.DisallowedPool;
                }
            }
            catch {
            }
        }
        addressStates[a] = state;
        return state;
    }
    
    // Not intended for external consumption
    // Always throws
    // We want to call functions to probe for things, but don't want to open ourselves up to
    // possible state-changes
    // So we return a value by reverting with a message
    function throwAddressState(address a) external view
    {
        try IUniswapV2Pair(a).factory() returns (address factory)
        {
            // don't care if it's some crappy alt-amm
            if (factory == address(uniswapV2Factory)) {
                // these checks for token0/token1 are just for additional
                // certainty that we're interacting with a uniswap pair
                try IUniswapV2Pair(a).token0() returns (address token0)
                {
                    if (token0 == address(neonVault)) {
                        revert("22");
                    }
                    try IUniswapV2Pair(a).token1() returns (address token1)
                    {
                        if (token1 == address(neonVault)) {
                            revert("22");
                        }                        
                    }
                    catch { 
                    }                    
                }
                catch { 
                }
            }
        }
        catch {             
        }
        revert("1");
    }
}