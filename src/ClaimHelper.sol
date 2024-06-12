// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

interface IVault {
    function claim(address user) external;
}

contract ClaimHelper {
    function claimAll(IVault[] calldata vaults, address user) external {
        for (uint i = 0; i < vaults.length; i++) {
            vaults[i].claim(user);
        }
    }

    function claimAll(IVault[] calldata vaults) external {
        for (uint i = 0; i < vaults.length; i++) {
            vaults[i].claim(msg.sender);
        }
    }
}