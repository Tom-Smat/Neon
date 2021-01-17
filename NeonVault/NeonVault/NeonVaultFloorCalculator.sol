// SPDX-License-Identifier: MIT!!!
pragma solidity ^0.7.4;

/* NEONVAULT:
A floor calculator (to use with ERC31337) for NeonVault uniswap pairs
Ensures 100% of accessible funds are backed at all times
*/

import "./IFloorCalculator.sol";
import "./NeonVault.sol";
import "./SafeMath.sol";
import "./UniswapV2Library.sol";
import "./IUniswapV2Factory.sol";
import "./TokensRecoverable.sol";
import "./INeonVaultDistribution.sol";

contract NeonVaultFloorCalculator is IFloorCalculator, TokensRecoverable
{
    using SafeMath for uint256;

    NeonVault immutable neonVault;
    IUniswapV2Factory immutable uniswapV2Factory;
    INeonVaultDistribution immutable neonVaultDistribution;

    constructor(NeonVault _neonVault, IUniswapV2Factory _uniswapV2Factory, INeonVaultDistribution _neonVaultDistribution)
    {
        neonVault = _neonVault;
        uniswapV2Factory = _uniswapV2Factory;
        neonVaultDistribution = _neonVaultDistribution;
    }

    function calculateSubFloor(IERC20 wrappedToken, IERC20 backingToken) public override view returns (uint256)
    {
        address pair = UniswapV2Library.pairFor(address(uniswapV2Factory), address(neonVault), address(backingToken));
        uint256 freeNeonVault = neonVaultDistribution.getTotalNeonSupplyForLge().sub(neonVault.balanceOf(pair));
        uint256 sellAllProceeds = 0;
        if (freeNeonVault > 0) {
            address[] memory path = new address[](2);
            path[0] = address(neonVault);
            path[1] = address(backingToken);
            uint256[] memory amountsOut = UniswapV2Library.getAmountsOut(address(uniswapV2Factory), freeNeonVault, path);
            sellAllProceeds = amountsOut[1];
        }
        uint256 backingInPool = backingToken.balanceOf(pair);
        if (backingInPool <= sellAllProceeds) { return 0; }
        uint256 excessInPool = backingInPool - sellAllProceeds;

        uint256 requiredBacking = backingToken.totalSupply().sub(excessInPool);
        uint256 currentBacking = wrappedToken.balanceOf(address(backingToken));
        if (requiredBacking >= currentBacking) { return 0; }
        return currentBacking - requiredBacking;
    }
}