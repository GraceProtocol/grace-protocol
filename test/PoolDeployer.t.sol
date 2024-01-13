// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/PoolDeployer.sol";

contract PoolDeployerTest is Test {

    PoolDeployer public poolDeployer;

    function setUp() public {
        poolDeployer = new PoolDeployer();
    }

    function test_deployPool() public {
        address payable pool = payable(poolDeployer.deployPool("Pool", "POOL", address(this), false));
        assertEq(Pool(pool).name(), "Pool");
        assertEq(Pool(pool).symbol(), "POOL");
        assertEq(Pool(pool).decimals(), 18);
        assertEq(address(Pool(pool).asset()), address(this));
        assertEq(address(Pool(pool).core()), address(this));
    }

}