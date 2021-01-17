// SPDX-License-Identifier: MIT!!!
pragma solidity ^0.7.4;

interface INeonVaultDistribution
{
    // function distributionComplete() external view returns (bool);
    function distribute() external payable;
    function claim(address _to, uint256 _contribution) external;
    function getTotalNeonSupplyForLge() external view returns (uint256);
}