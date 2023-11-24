// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/BondFactory.sol";
import "../src/RecurringBond.sol";
import "./mocks/ERC20.sol";

contract BondFactoryTest is Test {

    ERC20 public GRACE;
    BondFactory bondFactory;

    function setUp() public {
        GRACE = new ERC20();
        bondFactory = new BondFactory(address(GRACE), address(this));
    }

    function test_constructor() public {
        assertEq(address(bondFactory.GRACE()), address(GRACE));
        assertEq(bondFactory.operator(), address(this));
    }

    function test_createBond() public {

        uint startTimestamp = block.timestamp + 100;
        uint bondDuration = 100;
        uint auctionDuration = 10;
        uint initialRewardBudget = 1000;

        address bond = bondFactory.createBond(
            address(0x1),
            "name",
            "symbol",
            startTimestamp,
            bondDuration,
            auctionDuration,
            initialRewardBudget
        );

        assertEq(bondFactory.allBondsLength(), 1);
        assertEq(bondFactory.allBonds(0), address(bond));

        RecurringBond recurringBond = RecurringBond(bond);
        assertEq(address(recurringBond.asset()), address(0x1));
        assertEq(address(recurringBond.reward()), address(GRACE));
        assertEq(recurringBond.name(), "name");
        assertEq(recurringBond.symbol(), "symbol");
        assertEq(recurringBond.startTimestamp(), startTimestamp);
        assertEq(recurringBond.bondDuration(), bondDuration);
        assertEq(recurringBond.auctionDuration(), auctionDuration);
        assertEq(recurringBond.rewardBudget(), initialRewardBudget);
        assertEq(recurringBond.nextRewardBudget(), initialRewardBudget);
    }

    function test_setOperator() public {
        bondFactory.setOperator(address(1));
        assertEq(bondFactory.operator(), address(1));

        vm.expectRevert("onlyOperator"); // no longer operator
        bondFactory.setOperator(address(0x2));
    }

    function test_transferReward() public {
        address bond = bondFactory.createBond(
            address(0x1),
            "name",
            "symbol",
            block.timestamp + 100,
            100,
            10,
            1000
        );

        vm.expectRevert("onlyBond"); // not bond
        bondFactory.transferReward(address(1), 100);
        vm.prank(bond);
        bondFactory.transferReward(address(1), 100);
        assertEq(GRACE.balanceOf(address(1)), 100);
    }

    function test_setBudget() public {
        address bond = bondFactory.createBond(
            address(0x1),
            "name",
            "symbol",
            block.timestamp + 100,
            100,
            10,
            1000
        );

        vm.startPrank(address(1));
        vm.expectRevert("onlyOperator"); // not operator
        bondFactory.setBudget(bond, 100);
        vm.stopPrank();
        assertEq(RecurringBond(bond).rewardBudget(), 1000);
        assertEq(RecurringBond(bond).nextRewardBudget(), 1000);
        bondFactory.setBudget(bond, 100);
        assertEq(RecurringBond(bond).rewardBudget(), 100);
        assertEq(RecurringBond(bond).nextRewardBudget(), 100);
        vm.expectRevert("onlyBond"); // not bond
        bondFactory.setBudget(address(1), 100);
    }

}