// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/CollateralDeployer.sol";

contract CollateralDeployerTest is Test {

    CollateralDeployer public collateralDeployer;

    function setUp() public {
        collateralDeployer = new CollateralDeployer();
    }

    function test_deployCollateral() public {
        address collateral = collateralDeployer.deployCollateral(address(this), false);
        assertEq(address(Collateral(payable(collateral)).asset()), address(this));
        assertEq(address(Collateral(payable(collateral)).core()), address(this));
    }

}