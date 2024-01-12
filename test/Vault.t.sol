// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "./mocks/ERC20.sol";

contract VaultHandler is Test {

    ERC20 public pool;
    Vault public vault;

    uint public sumOfDeposits;

    constructor(Vault _vault, ERC20 _pool) {
        vault = _vault;
        pool = _pool;
    }

    function deposit(uint amount) public {
        pool.mint(address(this), amount);
        pool.approve(address(vault), amount);
        vault.depositShares(amount, address(this));
        sumOfDeposits += amount;
    }

    function withdraw(uint amount) public {
        amount = bound(amount, 0, sumOfDeposits);
        vault.withdrawShares(amount, address(this), address(this));
        sumOfDeposits -= amount;
    }

    function claim() public {
        vault.claim();
    }
}

contract MockPool is ERC20 {
    
    ERC20 public asset;

    constructor() {
        asset = new ERC20();
    }
}

contract VaultTest is Test {

    MockPool public pool;
    ERC20 public reward;
    Vault public vault;
    VaultHandler public handler;

    function setUp() public {
        pool = new MockPool();
        reward = new ERC20();
        vault = new Vault(
            address(pool),
            1000e18,
            false
        );
        handler = new VaultHandler(vault, pool);
    }

    // mock
    function transferReward(address to, uint amount) external {
        reward.mint(to, amount);
    }

    function invariant_totalSupply() public {
        assertEq(vault.totalSupply(), handler.sumOfDeposits());
    }

    function invariant_balanceOf() public {
        assertEq(vault.balanceOf(address(handler)), handler.sumOfDeposits());
    }

    function invariant_poolBalance() public {
        assertEq(vault.totalSupply(), pool.balanceOf(address(vault)));
    }

    function test_constructor() public {
        assertEq(address(vault.pool()), address(pool));
        assertEq(vault.rewardBudget(), 1000e18);
        assertEq(address(vault.factory()), address(this));
    }

    function test_deposit_withdraw(uint timestamp, uint amount) public {
        vm.warp(timestamp);
        handler.deposit(amount);
        // deposit
        assertEq(vault.balanceOf(address(handler)), amount);
        assertEq(vault.totalSupply(), amount);
        assertEq(pool.balanceOf(address(handler)), 0);
        assertEq(pool.balanceOf(address(vault)), amount);  
        // withdraw
        handler.withdraw(amount);
        assertEq(vault.balanceOf(address(handler)), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(pool.balanceOf(address(handler)), amount);
        assertEq(pool.balanceOf(address(vault)), 0);
    }

    function test_claimable() public {
        vm.warp(1);
        handler.deposit(1e18);
        vm.warp(365 days + 1);
        assertEq(vault.claimable(address(handler)), 1000e18);
        handler.claim();
        assertEq(reward.balanceOf(address(handler)), 1000e18);
    }

    function test_claim() public {
        vm.warp(1);
        handler.deposit(1e18);
        vm.warp(365 days + 1);
        assertEq(vault.claimable(address(handler)), 1000e18);
        handler.claim();
        assertEq(reward.balanceOf(address(handler)), 1000e18);
        assertEq(vault.claimable(address(handler)), 0);
        assertEq(vault.accruedRewards(address(handler)), 0);
    }


    function test_approve_withdrawOnBehalf() public {
        pool.mint(address(this), 2e18);
        pool.approve(address(vault), 2e18);
        vault.depositShares(1e18);
        vault.approve(address(1), 1e18);
        vm.prank(address(1));
        vault.withdrawShares(1e18, address(1), address(this));   
        assertEq(pool.balanceOf(address(1)), 1e18);          
    }

    function test_setBudget() public {
        vm.startPrank(address(1));
        vm.expectRevert("only factory");
        vault.setBudget(2000e18);
        vm.stopPrank();
        vault.setBudget(3000e18);
        assertEq(vault.rewardBudget(), 3000e18);
    }

}