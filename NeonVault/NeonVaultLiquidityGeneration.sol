// SPDX-License-Identifier: MIT!!!
pragma solidity ^0.7.4;

import "./Owned.sol";
import "./NeonVault.sol";
import "./INeonVaultDistribution.sol";
import "./TokensRecoverable.sol";

contract NeonVaultLiquidityGeneration is Owned, TokensRecoverable
{
    mapping (address => uint256) public contribution;
    address[] public contributors;

    bool public isActive;

    NeonVault immutable neonVault;
    INeonVaultDistribution public neonVaultDistribution;
    uint256 refundsAllowedUntil;

    constructor (NeonVault _neonVault)
    {
        neonVault = _neonVault;
    }

    modifier active()
    {
        require (isActive, "Distribution not active");
        _;
    }

    function contributorsCount() public view returns (uint256) { return contributors.length; }

    function activate(INeonVaultDistribution _neonVaultDistribution) public ownerOnly()
    {
        require (!isActive && contributors.length == 0 && block.timestamp >= refundsAllowedUntil, "Already activated");        
        // require (neonVault.balanceOf(address(this)) == neonVault.totalSupply(), "Missing supply");
        require (address(_neonVaultDistribution) != address(0));
        neonVaultDistribution = _neonVaultDistribution;
        isActive = true;
    }

    function setNeonVaultDistribution(INeonVaultDistribution _neonVaultDistribution) public ownerOnly() active()
    {
        require (address(_neonVaultDistribution) != address(0));
        if (_neonVaultDistribution == neonVaultDistribution) { return; }
        neonVaultDistribution = _neonVaultDistribution;

        // Give everyone 1 day to claim refunds if they don't approve of the new distributor
        refundsAllowedUntil = block.timestamp + 100;
    }

    function complete() public ownerOnly() active()
    {
        require (block.timestamp >= refundsAllowedUntil, "Refund period is still active");
        isActive = false;
        if (address(this).balance == 0) { return; }
        neonVault.approve(address(neonVaultDistribution), uint256(-1));
        neonVaultDistribution.distribute{ value: address(this).balance }();
    }

    function allowRefunds() public ownerOnly() active()
    {
        isActive = false;
        refundsAllowedUntil = uint256(-1);
    }

    function claim() public
    {
        uint256 amount = contribution[msg.sender];
        require (amount > 0, "Nothing to claim");
        contribution[msg.sender] = 0;
        if (refundsAllowedUntil > block.timestamp) {
            (bool success,) = msg.sender.call{ value: amount }("");
            require (success, "Transfer failed");
        }
        else {
            neonVaultDistribution.claim(msg.sender, amount);
        }
    }

    receive() external payable active()
    {
        uint256 oldContribution = contribution[msg.sender];
        uint256 newContribution = oldContribution + msg.value;
        if (oldContribution == 0 && newContribution > 0) {
            contributors.push(msg.sender);
        }
        contribution[msg.sender] = newContribution;
    }
}