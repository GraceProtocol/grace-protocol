// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/Reserve.sol";
import "./mocks/ERC20.sol";

contract ReserveTest is Test {

    ERC20 public gtr;
    Reserve public reserve;

    function setUp() public {
        gtr = new ERC20();
        reserve = new Reserve(address(gtr));
    }

    function test_constructor() public {
        assertEq(address(reserve.gtr()), address(gtr));
        assertEq(address(reserve.owner()), address(this));
    }

    function test_rageQuit() public {
        ERC20 backing = new ERC20();
        backing.mint(address(reserve), 1000);
        gtr.mint(address(this), 1000);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(backing));
        gtr.approve(address(reserve), 1000);

        reserve.rageQuit(500, tokens);        
        assertEq(backing.balanceOf(address(this)), 500);
        assertEq(gtr.balanceOf(address(this)), 500);
        assertEq(gtr.totalSupply(), 500);

        // no duplicates
        backing.mint(address(reserve), 1000);
        gtr.mint(address(this), 1000);
        IERC20[] memory duplicateTokens = new IERC20[](2);
        duplicateTokens[0] = IERC20(address(backing));
        duplicateTokens[1] = IERC20(address(backing));
        gtr.approve(address(reserve), 1000);
        vm.expectRevert("duplicate token");
        reserve.rageQuit(1000, duplicateTokens);

        // empty array
        IERC20[] memory emptyTokens = new IERC20[](0);
        vm.expectRevert("noTokens");
        reserve.rageQuit(1000, emptyTokens);

        // zero balance
        IERC20[] memory zeroBalTokens = new IERC20[](1);
        ERC20 zeroBalToken = new ERC20();
        zeroBalTokens[0] = IERC20(address(zeroBalToken));
        vm.expectRevert("zeroBalance");
        reserve.rageQuit(500, zeroBalTokens);
    }

    function test_allowance() public {
        ERC20 backing = new ERC20();
        backing.mint(address(reserve), 1000);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(backing));
        uint[] memory amounts = new uint[](1);
        amounts[0] = 1001; // more than balance
        reserve.requestAllowance(tokens, amounts, address(this));
        assertEq(reserve.getAllowanceRequestTimestamp(), block.timestamp);
        assertEq(reserve.getAllowanceRequestDst(), address(this));
        assertEq(reserve.getAllowanceRequestTokensLength(), 1);
        (address token, uint amount) = reserve.getAllowanceRequestTokens(0);
        assertEq(amount, 1001);
        assertEq(token, address(backing));
        vm.expectRevert("tooSoon");
        reserve.executeAllowance();
        vm.expectRevert("tooLate");
        vm.warp(block.timestamp + 60 days + 1);
        reserve.executeAllowance();
        vm.warp(block.timestamp - 14 days);
        reserve.executeAllowance();
        assertEq(backing.balanceOf(address(this)), 0);
        assertEq(backing.balanceOf(address(reserve)), 1000);
        assertEq(backing.allowance(address(reserve), address(this)), 1000);
        assertEq(reserve.getAllowanceRequestTimestamp(), 0);
        assertEq(reserve.getAllowanceRequestDst(), address(0));
        assertEq(reserve.getAllowanceRequestTokensLength(), 0);
    }

}