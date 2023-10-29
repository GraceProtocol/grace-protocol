// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/Pool.sol";
import "./mocks/ERC20.sol";
import "./mocks/MockCore.sol";

contract PoolTest is Test, MockCore {
    
    Pool public pool;
    ERC20 public asset;

    function setUp() public {
        asset = new ERC20();
        pool = new Pool(
            "Pool",
            "POOL",
            IPoolUnderlying(address(asset)),
            address(this)
        );
    }

    function test_constructor() public {
        assertEq(pool.name(), "Pool");
        assertEq(pool.symbol(), "POOL");
        assertEq(pool.decimals(), 18);
        assertEq(address(pool.asset()), address(asset));
        assertEq(address(pool.core()), address(this));
    }

    function test_deposit() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(1000, address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(this)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);   
        assertEq(pool.getAssetsOf(address(this)), 1000);  
    }

    function test_mint() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.mint(1000, address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(this)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 1000);
    }

    function test_withdraw() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        pool.withdraw(2000, address(this), address(this));
        pool.withdraw(1000, address(this), address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(this)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 1000);
    }

    function test_redeem() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        pool.redeem(2000, address(this), address(this));
        pool.redeem(1000, address(this), address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(this)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 1000);
    }

    function test_transfer() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(1000, address(this));
        pool.transfer(address(1), 1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(1)), 1000);
        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(1)), 1000);
        assertEq(pool.getAssetsOf(address(this)), 0);
    }

    function test_approve_transferFrom() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(1000, address(this));
        pool.approve(address(1), 1000);
        assertEq(pool.allowance(address(this), address(1)), 1000);
        vm.prank(address(1));
        pool.transferFrom(address(this), address(1), 1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(1)), 1000);
        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(1)), 1000);
        assertEq(pool.getAssetsOf(address(this)), 0);
        assertEq(pool.allowance(address(this), address(1)), 0);
    }

    function test_borrow_repay() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        pool.borrow(2000, address(this), address(this));
        pool.borrow(1000, address(this), address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(asset.balanceOf(address(this)), 1000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.totalDebt(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 1000);
        asset.approve(address(pool), 1000);
        pool.repay(address(this), 1000);
        assertEq(asset.balanceOf(address(pool)), 2000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.lastBalance(), 2000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 0);
    }

    function test_writeOff() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        pool.borrow(1000, address(this), address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(asset.balanceOf(address(this)), 1000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.totalDebt(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 1000);
        assertEq(pool.totalAssets(), 2000);
        assertEq(pool.totalDebt(), 1000);
        pool.writeOff(address(this));
        assertEq(pool.totalAssets(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.getAssetsOf(address(this)), 1000);
        assertEq(pool.getDebtOf(address(this)), 0);
    }

    function test_invalidateNonce() public {
        assertEq(pool.nonces(address(this)), 0);
        pool.invalidateNonce();
        assertEq(pool.nonces(address(this)), 1);
    }

}