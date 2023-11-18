// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/RecurringBond.sol";
import "./mocks/ERC20.sol";

contract RecurringBondHandler is Test {

    ERC20 public asset;
    ERC20 public reward;
    RecurringBond public bond;

    uint public sumOfDeposits;
    uint public sumOfPreorders;

    constructor(RecurringBond _bond, ERC20 _asset, ERC20 _reward) {
        bond = _bond;
        asset = _asset;
        reward = _reward;
    }

    function deposit(uint amount) public {
        asset.mint(address(this), amount);
        asset.approve(address(bond), amount);
        bond.deposit(amount, address(this));
        sumOfDeposits += amount;
    }

    function withdraw(uint amount) public {
        amount = bound(amount, 0, sumOfDeposits);
        bond.withdraw(amount, address(this), address(this));
        sumOfDeposits -= amount;
    }
}

contract RecurringBondTest is Test {

    ERC20 public asset;
    ERC20 public reward;
    RecurringBond public bond;
    RecurringBondHandler public handler;

    function setUp() public {
        asset = new ERC20();
        reward = new ERC20();
        bond = new RecurringBond(
            IERC20(address(asset)),
            IERC20(address(reward)),
            "Bond",
            "BOND",
            block.timestamp,
            7 days,
            1 days,
            1000e18
        );
        handler = new RecurringBondHandler(bond, asset, reward);
    }

    function test_constructor() public {
        assertEq(address(bond.asset()), address(asset));
        assertEq(address(bond.reward()), address(reward));
        assertEq(bond.name(), "Bond");
        assertEq(bond.symbol(), "BOND");
        assertEq(bond.startTimestamp(), block.timestamp);
        assertEq(bond.bondDuration(), 7 days);
        assertEq(bond.auctionDuration(), 1 days);
        assertEq(bond.rewardBudget(), 1000e18);
        assertEq(bond.nextRewardBudget(), 1000e18);
        assertEq(address(bond.factory()), address(this));

        // constraints
        vm.expectRevert("auctionDuration must be greater than 0");
        new RecurringBond(IERC20(address(asset)), IERC20(address(reward)), "Bond", "BOND", block.timestamp, 7 days, 0, 1000e18);

        vm.expectRevert("bondDuration must be greater than auctionDuration");
        new RecurringBond(IERC20(address(asset)), IERC20(address(reward)), "Bond", "BOND", block.timestamp, 7 days, 7 days, 1000e18);

        vm.expectRevert("startTimestamp must be now or in the future");
        new RecurringBond(IERC20(address(asset)), IERC20(address(reward)), "Bond", "BOND", block.timestamp - 1, 7 days, 1 days, 1000e18);
    }

    function invariant_deposits() public {
        assertEq(bond.deposits(), handler.sumOfDeposits());
    }

    function invariant_assetBalance() public {
        assertEq(bond.deposits(), asset.balanceOf(address(bond)));
    }

    function invariant_preorders() public {
        assertEq(bond.totalPreorders(), handler.sumOfPreorders());
    }

}