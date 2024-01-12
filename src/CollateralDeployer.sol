// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "./Collateral.sol";

contract CollateralDeployer {
    function deployCollateral(address underlying, bool isWETH) external returns (address collateral) {
        collateral = address(new Collateral(IERC20(underlying), isWETH, msg.sender));
    }
}