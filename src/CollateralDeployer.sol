// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./Collateral.sol";

contract CollateralDeployer {
    function deployCollateral(address underlying) external returns (address collateral) {
        collateral = address(new Collateral(ICollateralUnderlying(underlying), msg.sender));
    }
}