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
        if(bond.isAuctionActive()) {
            sumOfDeposits += amount;
        } else {
            sumOfPreorders += amount;
        }
    }

    function withdraw(uint amount) public {
        amount = bound(amount, 0, bond.isAuctionActive() ? sumOfDeposits : sumOfPreorders);
        bond.withdraw(amount, address(this), address(this));
        if(bond.isAuctionActive()) {
            sumOfDeposits -= amount;
        } else {
            sumOfPreorders -= amount;
        }
    }

    function claim() public {
        bond.claim();
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

    // mock
    function transferReward(address to, uint amount) external {
        reward.mint(to, amount);
    }

    function invariant_deposits() public {
        assertEq(bond.deposits(), handler.sumOfDeposits());
    }

    function invariant_totalSupply() public {
        assertEq(bond.totalSupply(), handler.sumOfDeposits() + handler.sumOfPreorders());
    }

    function invariant_bondBalances() public {
        assertEq(bond.balances(address(handler)), handler.sumOfDeposits());
    }

    function invariant_assetBalance() public {
        assertEq(bond.deposits(), asset.balanceOf(address(bond)));
    }

    function invariant_preorders() public {
        assertEq(bond.totalPreorders(), handler.sumOfPreorders());
        assertEq(bond.preorderOf(address(handler)), handler.sumOfPreorders());
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

    function test_deposit_withdraw(uint timestamp, uint amount) public {
        vm.warp(timestamp);
        handler.deposit(amount);
        if(bond.isAuctionActive()) {
            // deposit
            assertEq(bond.balances(address(handler)), amount);
            assertEq(bond.balanceOf(address(handler)), amount);
            assertEq(bond.deposits(), amount);
            assertEq(asset.balanceOf(address(handler)), 0);
            assertEq(asset.balanceOf(address(bond)), amount);  
            // withdraw
            handler.withdraw(amount);
            assertEq(bond.balances(address(handler)), 0);
            assertEq(bond.balanceOf(address(handler)), 0);
            assertEq(bond.deposits(), 0);
            assertEq(asset.balanceOf(address(handler)), amount);
            assertEq(asset.balanceOf(address(bond)), 0);
        } else {
            // preorder
            assertEq(bond.preorderOf(address(handler)), amount);
            assertEq(bond.accountCyclePreorder(address(handler), bond.getCycle()), amount);
            assertEq(bond.cyclePreorders(bond.getCycle()), amount);
            assertEq(bond.balances(address(handler)), amount);
            assertEq(bond.balanceOf(address(handler)), 0);
            assertEq(bond.deposits(), amount);
            assertEq(asset.balanceOf(address(handler)), 0);
            assertEq(asset.balanceOf(address(bond)), amount);
            // cancel preorder
            handler.withdraw(amount);
            assertEq(bond.preorderOf(address(handler)), 0);
            assertEq(bond.accountCyclePreorder(address(handler), bond.getCycle()), 0);
            assertEq(bond.cyclePreorders(bond.getCycle()), 0);
            assertEq(bond.balances(address(handler)), 0);
            assertEq(bond.balanceOf(address(handler)), 0);
            assertEq(bond.deposits(), 0);
            assertEq(asset.balanceOf(address(handler)), amount);
            assertEq(asset.balanceOf(address(bond)), 0);
        }
    }

    function test_isAuctionActive(uint cycle) public {
        cycle = cycle == 0 ? 1 : cycle;
        cycle = bound(cycle, 1, 1e18);
        vm.warp(cycle * 7 days + 1);
        assertEq(bond.isAuctionActive(), true);
        vm.warp(cycle * 7 days + 1 days + 1);
        assertEq(bond.isAuctionActive(), false);
    }

    function test_getCycle() public {
        assertEq(bond.getCycle(), 1);
        vm.warp(7 days + 1);
        assertEq(bond.getCycle(), 2);
    }

    function test_claimable() public {
        vm.warp(1);
        handler.deposit(1e18);
        vm.warp(7 days + 1);
        assertEq(bond.claimable(address(handler)), 1000e18);
        handler.claim();
        assertEq(reward.balanceOf(address(handler)), 1000e18);
    }

    function test_claimableAfterPreorder() public {
        vm.warp(1 days + 1);
        handler.deposit(1e18);
        assertEq(bond.claimable(address(handler)), 0);
        handler.claim();
        assertEq(reward.balanceOf(address(handler)), 0);
        vm.warp(7 days + 1);
        assertEq(bond.claimable(address(handler)), 0);
        handler.claim();
        assertEq(reward.balanceOf(address(handler)), 0);
        vm.warp(14 days + 1);
        assertEq(bond.claimable(address(handler)), 1000e18);
        handler.claim();
        assertEq(reward.balanceOf(address(handler)), 1000e18);
    }

}