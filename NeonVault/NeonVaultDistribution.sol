// SPDX-License-Identifier: MIT!!!
pragma solidity ^0.7.4;

import "./INeonVaultDistribution.sol";
import "./Owned.sol";
import "./NeonVault.sol";
import "./NeonVaultTransferGate.sol";
import "./TokensRecoverable.sol";
import "./SafeMath.sol";
import "./NETH.sol";
import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IWrappedERC20.sol";

/*
Phases:
    Initializing
        Call setupKethNeonVault()
        Call completeSetup()
        
    Call distribute() to:
        Transfer all NeonVault to this contract
        Take all ETH + NeonVault and create a market
        Buy NeonVault
        Buy NeonVault for the group
        Distribute funds

    Complete
        Everyone can call claim() to receive their tokens (via the liquidity generation contract)
*/

contract NeonVaultDistribution is Owned, TokensRecoverable, INeonVaultDistribution
{
    using SafeMath for uint256;

    bool public distributionComplete;

    IUniswapV2Router02 immutable uniswapV2Router;
    IUniswapV2Factory immutable uniswapV2Factory;
    NeonVault immutable neonVault;
    NETH immutable neth;
    IERC20 immutable weth;
    address immutable vault;

    IUniswapV2Pair nethNeonVault;
    IWrappedERC20 wrappedNethNeonVault;

    uint256 public totalEthCollected;
    uint256 public totalNeonVaultBought;
    uint256 public totalNethNeonVault;
    address neonVaultLiquidityGeneration;
    uint256 recoveryDate = block.timestamp + 2592000; // 1 Month

    uint8 public jengaCount;
    
    // 10000 = 100%
    uint16 constant public vaultPercent = 2500; // Proportionate amount used to seed the vault
    uint16 constant public buyPercent = 2500; // Proportionate amount used to group buy NeonVault for distribution to participants
   
    constructor(NeonVault _neonVault, IUniswapV2Router02 _uniswapV2Router, NETH _neth, address _vault)
    {
        require (address(_neonVault) != address(0));
        require (address(_vault) != address(0));

        neonVault = _neonVault;
        uniswapV2Router = _uniswapV2Router;
        neth = _neth;
        vault = _vault;

        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Router.factory());
        weth = _neth.wrappedToken();
    }

    function setupKethNeonVault() public
    {
        nethNeonVault = IUniswapV2Pair(uniswapV2Factory.getPair(address(neth), address(neonVault)));
        if (address(nethNeonVault) == address(0)) {
            nethNeonVault = IUniswapV2Pair(uniswapV2Factory.createPair(address(neth), address(neonVault)));
            require (address(nethNeonVault) != address(0));
        }
    }
    
    function completeSetup(IWrappedERC20 _wrappedNethNeonVault) public ownerOnly()
    {        
        require (address(_wrappedNethNeonVault.wrappedToken()) == address(nethNeonVault), "Wrong LP Wrapper");
        wrappedNethNeonVault = _wrappedNethNeonVault;
        neth.approve(address(uniswapV2Router), uint256(-1));
        neonVault.approve(address(uniswapV2Router), uint256(-1));
        weth.approve(address(neth), uint256(-1));
        weth.approve(address(uniswapV2Router), uint256(-1));
        nethNeonVault.approve(address(wrappedNethNeonVault), uint256(-1));
    }

    function setJengaCount(uint8 _jengaCount) public ownerOnly()
    {
        jengaCount = _jengaCount;
    }

    function distribute() public override payable
    {
        require (!distributionComplete, "Distribution complete");
        uint256 totalEth = msg.value;
        require (totalEth > 0, "Nothing to distribute");
        distributionComplete = true;
        totalEthCollected = totalEth;
        neonVaultLiquidityGeneration = msg.sender;

        neonVault.transferFrom(msg.sender, address(this), neonVault.totalSupply());
        
        NeonVaultTransferGate gate = NeonVaultTransferGate(address(neonVault.transferGate()));
        gate.setUnrestricted(true);

        createNethNeonVaultLiquidity(totalEth);

        jenga(jengaCount);

        sweepFloorToWeth();
        uint256 wethBalance = weth.balanceOf(address(this));

        preBuyForGroup(wethBalance * buyPercent / 10000);

        sweepFloorToWeth();
        weth.transfer(vault, wethBalance * vaultPercent / 10000);
        weth.transfer(owner, weth.balanceOf(address(this)));
        nethNeonVault.transfer(owner, nethNeonVault.balanceOf(address(this)));

        gate.setUnrestricted(false);
    }

    function sweepFloorToWeth() private
    {
        neth.sweepFloor(address(this));
        neth.withdrawTokens(neth.balanceOf(address(this)));
    }
    function createNethNeonVaultLiquidity(uint256 totalEth) private
    {
        // Create NETH/NEONVAULT LP 
        neth.deposit{ value: totalEth }();
        (,,totalNethNeonVault) = uniswapV2Router.addLiquidity(address(neth), address(neonVault), neth.balanceOf(address(this)), neonVault.totalSupply(), 0, 0, address(this), block.timestamp);
        
        // Wrap the NETH/NEONVAULT LP for distribution
        wrappedNethNeonVault.depositTokens(totalNethNeonVault);  
    }
   
    function preBuyForGroup(uint256 wethAmount) private
    {      
        address[] memory path = new address[](2);
        path[0] = address(neth);
        path[1] = address(neonVault);
        neth.depositTokens(wethAmount);
        uint256[] memory amountsNeonVault = uniswapV2Router.swapExactTokensForTokens(wethAmount, 0, path, address(this), block.timestamp);
        totalNeonVaultBought = amountsNeonVault[1];
    }
    
    function jenga(uint8 count) private
    {
        address[] memory path = new address[](2);
        path[0] = address(neth);
        path[1] = address(neonVault);
        for (uint x=0; x<count; ++x) {
            neth.depositTokens(neth.sweepFloor(address(this)));
            uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(neth.balanceOf(address(this)) * 2 / 5, 0, path, address(this), block.timestamp);
            neth.depositTokens(neth.sweepFloor(address(this)));
            uniswapV2Router.addLiquidity(address(neth), address(neonVault), neth.balanceOf(address(this)), amounts[1], 0, 0, address(this), block.timestamp);
        }
    }

    function claim(address _to, uint256 _contribution) public override
    {
        require (msg.sender == neonVaultLiquidityGeneration, "Unauthorized");
        uint256 totalEth = totalEthCollected;

        // Send NETH/NEONVAULT liquidity tokens
        uint256 share = _contribution.mul(totalNethNeonVault) / totalEth;        
        if (share > wrappedNethNeonVault.balanceOf(address(this))) {
            share = wrappedNethNeonVault.balanceOf(address(this)); // Should never happen, but just being safe.
        }
        wrappedNethNeonVault.transfer(_to, share);

        // Send NeonVault
        NeonVaultTransferGate gate = NeonVaultTransferGate(address(neonVault.transferGate()));
        gate.setUnrestricted(true);

        share = _contribution.mul(totalNeonVaultBought) / totalEth;
        if (share > neonVault.balanceOf(address(this))) {
            share = neonVault.balanceOf(address(this)); // Should never happen, but just being safe.
        }
        neonVault.transfer(_to, share);

        gate.setUnrestricted(false);
    }

    function canRecoverTokens(IERC20 token) internal override view returns (bool) { 
        return 
            block.timestamp > recoveryDate ||
            (
                token != neonVault && 
                address(token) != address(wrappedNethNeonVault) 
            );
    }
}