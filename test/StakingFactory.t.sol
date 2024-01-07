// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/StakingFactory.sol";
import "../src/StakingPool.sol";
import "./mocks/ERC20.sol";

contract StakingFactoryTest is Test {

    ERC20 public GRACE;
    StakingFactory stakingFactory;

    function setUp() public {
        GRACE = new ERC20();
        stakingFactory = new StakingFactory(address(GRACE));
    }

    function test_constructor() public {
        assertEq(address(stakingFactory.GRACE()), address(GRACE));
        assertEq(stakingFactory.operator(), address(this));
    }

    function test_createPool() public {

        uint initialRewardBudget = 1000;

        address pool = stakingFactory.createPool(
            address(0x1),
            initialRewardBudget
        );

        assertEq(stakingFactory.allPoolsLength(), 1);
        assertEq(stakingFactory.allPools(0), address(pool));

        StakingPool stakingPool = StakingPool(pool);
        assertEq(address(stakingPool.asset()), address(0x1));
        assertEq(address(stakingPool.reward()), address(GRACE));
        assertEq(stakingPool.rewardBudget(), initialRewardBudget);
    }

    function test_setOperator() public {
        stakingFactory.setOperator(address(1));
        assertEq(stakingFactory.operator(), address(1));

        vm.expectRevert("onlyOperator"); // no longer operator
        stakingFactory.setOperator(address(0x2));
    }

    function test_transferReward() public {
        address pool = stakingFactory.createPool(
            address(0x1),
            1000
        );

        vm.expectRevert("onlyPool"); // not pool
        stakingFactory.transferReward(address(1), 100);
        vm.prank(pool);
        stakingFactory.transferReward(address(1), 100);
        assertEq(GRACE.balanceOf(address(1)), 100);
    }

    function test_setBudget() public {
        address pool = stakingFactory.createPool(
            address(0x1),
            1000
        );

        vm.startPrank(address(1));
        vm.expectRevert("onlyOperator"); // not operator
        stakingFactory.setBudget(pool, 100);
        vm.stopPrank();
        assertEq(StakingPool(pool).rewardBudget(), 1000);
        stakingFactory.setBudget(pool, 100);
        assertEq(StakingPool(pool).rewardBudget(), 100);
        vm.expectRevert("onlyPool"); // not pool
        stakingFactory.setBudget(address(1), 100);
    }

}