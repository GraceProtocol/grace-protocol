// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./Collateral.sol";

contract CollateralDeployer {
    function deployCollateral(string memory name, string memory symbol, address underlying) external returns (address collateral) {
        collateral = address(new Collateral(name, symbol, IERC20(underlying), msg.sender));
    }
}