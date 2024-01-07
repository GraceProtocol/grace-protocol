// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/StakingPool.sol";
import "./mocks/ERC20.sol";

contract StakingPoolHandler is Test {

    ERC20 public asset;
    ERC20 public reward;
    StakingPool public pool;

    uint public sumOfDeposits;

    constructor(StakingPool _pool, ERC20 _asset, ERC20 _reward) {
        pool = _pool;
        asset = _asset;
        reward = _reward;
    }

    function deposit(uint amount) public {
        asset.mint(address(this), amount);
        asset.approve(address(pool), amount);
        pool.deposit(amount, address(this));
        sumOfDeposits += amount;
    }

    function withdraw(uint amount) public {
        amount = bound(amount, 0, sumOfDeposits);
        pool.withdraw(amount, address(this), address(this));
        sumOfDeposits -= amount;
    }

    function claim() public {
        pool.claim();
    }
}

contract StakingPoolTest is Test {

    ERC20 public asset;
    ERC20 public reward;
    StakingPool public pool;
    StakingPoolHandler public handler;

    function setUp() public {
        asset = new ERC20();
        reward = new ERC20();
        pool = new StakingPool(
            IERC20(address(asset)),
            IERC20(address(reward)),
            1000e18
        );
        handler = new StakingPoolHandler(pool, asset, reward);
    }

    // mock
    function transferReward(address to, uint amount) external {
        reward.mint(to, amount);
    }

    function invariant_totalSupply() public {
        assertEq(pool.totalSupply(), handler.sumOfDeposits());
    }

    function invariant_balanceOf() public {
        assertEq(pool.balanceOf(address(handler)), handler.sumOfDeposits());
    }

    function invariant_assetBalance() public {
        assertEq(pool.totalSupply(), asset.balanceOf(address(pool)));
    }

    function test_constructor() public {
        assertEq(address(pool.asset()), address(asset));
        assertEq(address(pool.reward()), address(reward));
        assertEq(pool.rewardBudget(), 1000e18);
        assertEq(address(pool.factory()), address(this));
    }

    function test_deposit_withdraw(uint timestamp, uint amount) public {
        vm.warp(timestamp);
        handler.deposit(amount);
        // deposit
        assertEq(pool.balanceOf(address(handler)), amount);
        assertEq(pool.totalSupply(), amount);
        assertEq(asset.balanceOf(address(handler)), 0);
        assertEq(asset.balanceOf(address(pool)), amount);  
        // withdraw
        handler.withdraw(amount);
        assertEq(pool.balanceOf(address(handler)), 0);
        assertEq(pool.totalSupply(), 0);
        assertEq(asset.balanceOf(address(handler)), amount);
        assertEq(asset.balanceOf(address(pool)), 0);
    }

    function test_claimable() public {
        vm.warp(1);
        handler.deposit(1e18);
        vm.warp(7 days + 1);
        assertEq(pool.claimable(address(handler)), 1000e18);
        handler.claim();
        assertEq(reward.balanceOf(address(handler)), 1000e18);
    }

    function test_claim() public {
        vm.warp(1);
        handler.deposit(1e18);
        vm.warp(7 days + 1);
        assertEq(pool.claimable(address(handler)), 1000e18);
        handler.claim();
        assertEq(reward.balanceOf(address(handler)), 1000e18);
        assertEq(pool.claimable(address(handler)), 0);
        assertEq(pool.accruedRewards(address(handler)), 0);
    }


    function test_approve_withdrawOnBehalf() public {
        asset.mint(address(this), 2e18);
        asset.approve(address(pool), 2e18);
        pool.deposit(1e18);
        pool.approve(address(1), 1e18);
        vm.prank(address(1));
        pool.withdraw(1e18, address(1), address(1));   
        assertEq(asset.balanceOf(address(1)), 1e18);          
    }

    function test_setBudget() public {
        vm.startPrank(address(1));
        vm.expectRevert("only factory");
        pool.setBudget(2000e18);
        vm.stopPrank();

        handler.deposit(1e18); // we'll need it to claim

        pool.setBudget(2000e18);
        assertEq(pool.rewardBudget(), 1000e18); // auction active

        vm.warp(1 days);
        handler.claim(); // trigger budget change
        assertEq(pool.rewardBudget(), 2000e18);
        pool.setBudget(3000e18);
        assertEq(pool.rewardBudget(), 3000e18); // auction inactive
    }

}