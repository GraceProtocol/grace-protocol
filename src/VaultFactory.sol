// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import "./Vault.sol";

interface IGTR {
    function mint(address recipient, uint amount) external;
}

contract VaultFactory {

    IGTR public immutable gtr;
    address public operator;
    mapping (address => bool) public isVault;
    address[] public allVaults;

    constructor (address _gtr) {
        gtr = IGTR(_gtr);
        operator = msg.sender;
    }

    function allVaultsLength() external view returns (uint) {
        return allVaults.length;
    }

    function createVault(
        address asset,
        uint initialRewardBudget
    ) external returns (address vault) {
        require(msg.sender == operator, "onlyOperator");
        vault = address(new Vault(
            IERC20(asset),
            initialRewardBudget
        ));
        isVault[vault] = true;
        allVaults.push(vault);
        emit VaultCreated(vault);
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "onlyOperator");
        operator = _operator;
    }

    function transferReward(address recipient, uint amount) external {
        require(isVault[msg.sender], "onlyVault");
        gtr.mint(recipient, amount);
    }

    function setBudget(address vault, uint budget) external {
        require(msg.sender == operator, "onlyOperator");
        require(isVault[vault], "onlyVault");
        Vault(vault).setBudget(budget);
    }

    event VaultCreated(address vault);

}