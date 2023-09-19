// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/BaseCollateral.sol";
import "./mocks/ERC20.sol";
import "./mocks/MockCore.sol";

contract BaseCollateralTest is Test {
    
    uint constant sqrtMaxUint = 340282366920938463463374607431768211455;
    ERC20 public token;
    MockCore public mockCore;
    BaseCollateral public baseCollateral;

    constructor() {
        token = new ERC20();
        mockCore = new MockCore();
        baseCollateral = new BaseCollateral(IERC20(address(token)));
        token.mint(address(this), type(uint256).max);
        token.approve(address(baseCollateral), type(uint256).max);
    }
    
    function testDeposit(uint amount) public {
        amount = bound(amount, 1001, sqrtMaxUint);
        uint MINIMUM_LIQUIDITY = 1000;
        baseCollateral.deposit(address(this), amount);
        assertEq(baseCollateral.sharesSupply(), amount);
        assertEq(baseCollateral.sharesOf(address(this)), amount - MINIMUM_LIQUIDITY);
        assertEq(baseCollateral.getCollateralOf(address(this)), amount - MINIMUM_LIQUIDITY);
        assertEq(token.balanceOf(address(baseCollateral)), amount);
    }

    function testDepositDenied() public {
        mockCore.setValue(false);
        vm.expectRevert();
        baseCollateral.deposit(address(this), 100);
        assertEq(baseCollateral.sharesSupply(), 0);
        assertEq(baseCollateral.sharesOf(address(this)), 0);
        assertEq(baseCollateral.getCollateralOf(address(this)), 0);
        assertEq(token.balanceOf(address(baseCollateral)), 0);
    }

    function testDepositOnBehalf(uint amount) public {
        amount = bound(amount, 1001, sqrtMaxUint);
        baseCollateral.deposit(address(1), amount);
        assertEq(baseCollateral.sharesSupply(), amount);
        assertEq(baseCollateral.sharesOf(address(1)), amount - 1000);
        assertEq(baseCollateral.getCollateralOf(address(1)), amount - 1000);
        assertEq(token.balanceOf(address(baseCollateral)), amount);
    }

    function testDepositZero() public {
        vm.expectRevert();
        baseCollateral.deposit(address(this), 0);
        assertEq(baseCollateral.sharesSupply(), 0);
        assertEq(baseCollateral.sharesOf(address(this)), 0);
        assertEq(baseCollateral.getCollateralOf(address(this)), 0);
        assertEq(token.balanceOf(address(baseCollateral)), 0);
    }

    function testSecondDeposit(uint amount) public {
        amount = bound(amount, 1001, sqrtMaxUint / 2);
        baseCollateral.deposit(address(this), amount);
        baseCollateral.deposit(address(this), amount);
        assertEq(baseCollateral.sharesSupply(), amount * 2);
        assertEq(baseCollateral.sharesOf(address(this)), amount * 2 - 1000);
        assertEq(baseCollateral.getCollateralOf(address(this)), amount * 2 - 1000);
        assertEq(token.balanceOf(address(baseCollateral)), amount * 2);
    }

    // function testDepositAfterWithdrawal(uint amount) public {
    //     amount = bound(amount, 1, sqrtMaxUint / 2);
    //     baseCollateral.deposit(address(this), amount);
    //     baseCollateral.withdraw(amount);
    //     baseCollateral.deposit(address(this), amount);
    //     assertEq(baseCollateral.sharesSupply(), amount);
    //     assertEq(baseCollateral.sharesOf(address(this)), amount);
    //     assertEq(baseCollateral.getCollateralOf(address(this)), amount);
    //     assertEq(token.balanceOf(address(baseCollateral)), amount);
    // }

    // function testDepositAfterPartialWithdrawal(uint amount) public {
    //     amount = bound(amount, 1001, sqrtMaxUint / 2);
    //     baseCollateral.deposit(address(this), amount);
    //     baseCollateral.withdraw(amount / 2);
    //     baseCollateral.deposit(address(this), amount);
    //     assertApproxEqAbs(baseCollateral.sharesSupply(), amount * 15 / 10, 1);
    //     assertApproxEqAbs(baseCollateral.sharesOf(address(this)), amount * 15 / 10, 1);
    //     assertApproxEqAbs(baseCollateral.getCollateralOf(address(this)), amount * 15 / 10, 1);
    //     assertApproxEqAbs(token.balanceOf(address(baseCollateral)), amount * 15 / 10, 1);
    // }
    
    function testWithdraw(uint amount) public {
        amount = bound(amount, 1001, sqrtMaxUint);
        baseCollateral.deposit(address(this), amount);
        baseCollateral.withdraw(amount - 1000);
        assertEq(baseCollateral.sharesSupply(), 1000);
        assertEq(baseCollateral.sharesOf(address(this)), 0);
        assertEq(baseCollateral.getCollateralOf(address(this)), 0);
        assertEq(token.balanceOf(address(baseCollateral)), 1000);
    }

    function testWithdrawDenied() public {
        baseCollateral.deposit(address(this), 1001);
        mockCore.setValue(false);
        vm.expectRevert();
        baseCollateral.withdraw(1);
        assertEq(baseCollateral.sharesSupply(), 1001);
        assertEq(baseCollateral.sharesOf(address(this)), 1);
        assertEq(baseCollateral.getCollateralOf(address(this)), 1);
        assertEq(token.balanceOf(address(baseCollateral)), 1001);
    }

    function testWithdrawZero() public {
        baseCollateral.deposit(address(this), 1001);
        vm.expectRevert();
        baseCollateral.withdraw(0);
        assertEq(baseCollateral.sharesSupply(), 1001);
        assertEq(baseCollateral.sharesOf(address(this)), 1);
        assertEq(baseCollateral.getCollateralOf(address(this)), 1);
        assertEq(token.balanceOf(address(baseCollateral)), 1001);
    }
    
    function testWithdrawPartial(uint amount) public {
        amount = bound(amount, 1, sqrtMaxUint - 1000);
        baseCollateral.deposit(address(this), sqrtMaxUint);
        baseCollateral.withdraw(amount);
        assertEq(baseCollateral.sharesSupply(), sqrtMaxUint - amount);
        assertEq(baseCollateral.sharesOf(address(this)), sqrtMaxUint - amount - 1000);
        assertEq(baseCollateral.getCollateralOf(address(this)), sqrtMaxUint - amount - 1000);
        assertEq(token.balanceOf(address(baseCollateral)), sqrtMaxUint - amount);

    }

    // function testWithdrawMoreThanDeposited(uint amount) public {
    //     amount = bound(amount, 1, sqrtMaxUint - 1);
    //     baseCollateral.deposit(address(this), amount);
    //     vm.expectRevert();
    //     baseCollateral.withdraw(amount + 1);
    //     assertEq(baseCollateral.sharesSupply(), amount);
    //     assertEq(baseCollateral.sharesOf(address(this)), amount);
    //     assertEq(baseCollateral.getCollateralOf(address(this)), amount);
    //     assertEq(token.balanceOf(address(baseCollateral)), amount);
    // }

    // function testSeize(uint amount) public {
    //     amount = bound(amount, 1, sqrtMaxUint);
    //     baseCollateral.deposit(address(this), amount);
    //     vm.prank(address(mockCore));
    //     baseCollateral.seize(address(this), amount);
    //     assertEq(baseCollateral.sharesSupply(), 0);
    //     assertEq(baseCollateral.sharesOf(address(this)), 0);
    //     assertEq(baseCollateral.getCollateralOf(address(this)), 0);
    //     assertEq(token.balanceOf(address(baseCollateral)), 0);
    // }
    
    // function testSeizeUnauthorized() public {
    //     baseCollateral.deposit(address(this), 100);
    //     vm.expectRevert();
    //     baseCollateral.seize(address(this), 100);
    //     assertEq(baseCollateral.sharesSupply(), 100);
    //     assertEq(baseCollateral.sharesOf(address(this)), 100);
    //     assertEq(baseCollateral.getCollateralOf(address(this)), 100);
    //     assertEq(token.balanceOf(address(baseCollateral)), 100);
    // }

    // function testGetCollateralOfAfter1YearFee() public {
    //     baseCollateral.deposit(address(this), 100);
    //     assertEq(baseCollateral.getCollateralOf(address(this)), 100);
    //     mockCore.setCollateralFeeBps(10000, address(this));
    //     vm.warp(block.timestamp + 365 days);
    //     assertEq(baseCollateral.getCollateralOf(address(this)), 0);
    // }

    // function testGetCollateralOfAfter6MonthsFee() public {
    //     baseCollateral.deposit(address(this), 100);
    //     assertEq(baseCollateral.getCollateralOf(address(this)), 100);
    //     mockCore.setCollateralFeeBps(10000, address(this));
    //     vm.warp(block.timestamp + (365 days / 2));
    //     assertEq(baseCollateral.getCollateralOf(address(this)), 50);
    // }

    // function testGetCollateralOfAfter2Years() public {
    //     baseCollateral.deposit(address(this), 100);
    //     assertEq(baseCollateral.getCollateralOf(address(this)), 100);
    //     mockCore.setCollateralFeeBps(10000, address(this));
    //     vm.warp(block.timestamp + 2 * 365 days);
    //     assertEq(baseCollateral.getCollateralOf(address(this)), 0);
    // }

    function testAccrueFee() public {
        uint feeBps = 10000;
        uint amount = 1000;
        uint MINIMUM_LIQUIDITY = 1000;
        baseCollateral.deposit(address(this), amount + MINIMUM_LIQUIDITY);
        assertEq(token.balanceOf(address(baseCollateral)), amount + MINIMUM_LIQUIDITY);
        mockCore.setCollateralFeeBps(feeBps, address(this));
        vm.warp(block.timestamp + 365 days);
        baseCollateral.accrueFee();
        assertEq(token.balanceOf(address(baseCollateral)), 1000);
        assertEq(baseCollateral.getCollateralOf(address(this)), 500);
    }

}