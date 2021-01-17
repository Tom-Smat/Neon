// SPDX-License-Identifier: MIT!!!
pragma solidity ^0.7.4;

/* NEONVAULT:
NeonVault
Because my suggestions of WootKit and GrootKit were overruled
*/

import "./GatedERC20.sol";

contract NeonVault is GatedERC20("Neon Vault Finance", "NEON")
{
    constructor()
    {
        _mint(msg.sender, 10000 ether);
    }
}
