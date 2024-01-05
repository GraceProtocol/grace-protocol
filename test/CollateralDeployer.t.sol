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
        address collateral = collateralDeployer.deployCollateral("Collateral", "COLL", address(this));
        assertEq(Collateral(collateral).name(), "Collateral");
        assertEq(Collateral(collateral).symbol(), "COLL");
        assertEq(Collateral(collateral).decimals(), 18);
        assertEq(address(Collateral(collateral).asset()), address(this));
        assertEq(address(Collateral(collateral).core()), address(this));
    }

}