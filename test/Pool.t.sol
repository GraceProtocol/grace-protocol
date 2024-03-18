// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

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
            IERC20(address(asset)),
            false,
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
        assertEq(pool.isDepositor(address(this)), true);
        assertEq(pool.depositors(0), address(this));
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
        assertEq(pool.isDepositor(address(this)), true);
        assertEq(pool.depositors(0), address(this));
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
        assertEq(pool.isDepositor(address(1)), true);
        assertEq(pool.depositors(1), address(1));
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
        assertEq(pool.isDepositor(address(1)), true);
        assertEq(pool.depositors(1), address(1));
    }

    function test_borrow_repay() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        pool.borrow(2000, address(this), address(this), address(0));
        pool.borrow(1000, address(this), address(this), address(0));
        assertEq(pool.isBorrower(address(this)), true);
        assertEq(pool.borrowers(0), address(this));
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
        pool.borrow(1000, address(this), address(this), address(0));
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

    function test_accrueInterest() public {
        uint DEPOSIT = 2000;
        uint BORROW = 1000;
        uint INTEREST = 1000;
        asset.mint(address(this), DEPOSIT + INTEREST);
        asset.approve(address(pool), DEPOSIT + BORROW + INTEREST);
        pool.deposit(DEPOSIT, address(this));
        pool.borrow(BORROW, address(this), address(this), address(0));
        vm.warp(block.timestamp + 365 days);
        // mock core sets borrow rate to 100%, so we expect 1000 interest
        assertEq(pool.getDebtOf(address(this)), BORROW + INTEREST);
        assertEq(pool.getAssetsOf(address(this)), DEPOSIT);
        pool.repay(address(this), BORROW + INTEREST);
        assertEq(pool.getAssetsOf(address(1)), INTEREST);
        assertEq(pool.balanceOf(address(1)), INTEREST);
        assertEq(pool.totalSupply(), DEPOSIT + INTEREST);
        assertEq(pool.lastBorrowRate(), 10000);
        assertEq(pool.lastBalance(), DEPOSIT + INTEREST);
    }

    function test_approveBorrow () public {
        pool.approveBorrow(address(1), type(uint256).max);
        assertEq(pool.borrowAllowance(address(this), address(1)), type(uint256).max);
    }

    function test_pull() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(1000, address(this));
        vm.expectRevert("cannotPullUnderlying");
        pool.pull(address(asset), address(1), 1000);
        ERC20 stuckToken = new ERC20();
        stuckToken.mint(address(pool), 1000);
        pool.pull(address(stuckToken), address(this), 1000);
        assertEq(stuckToken.balanceOf(address(pool)), 0);
        assertEq(stuckToken.balanceOf(address(this)), 1000);
    }
}