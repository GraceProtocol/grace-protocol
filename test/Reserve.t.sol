// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/Reserve.sol";
import "./mocks/ERC20.sol";

contract ReserveTest is Test {

    ERC20 public grace;
    Reserve public reserve;

    function setUp() public {
        grace = new ERC20();
        reserve = new Reserve(IERC20(address(grace)), address(this));
    }

    function test_constructor() public {
        assertEq(address(reserve.grace()), address(grace));
        assertEq(address(reserve.owner()), address(this));
    }

    function test_rageQuit() public {
        ERC20 backing = new ERC20();
        backing.mint(address(reserve), 1000);
        grace.mint(address(this), 1000);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(backing));
        grace.approve(address(reserve), 1000);
        vm.warp(1 days);

        // not first day of month
        vm.expectRevert("Only first day of each month");
        reserve.rageQuit(1000, tokens);

        // success case
        vm.warp(0);
        reserve.rageQuit(500, tokens);        
        assertEq(backing.balanceOf(address(this)), 500);
        assertEq(grace.balanceOf(address(this)), 500);
        assertEq(grace.totalSupply(), 500);

        // no duplicates
        backing.mint(address(reserve), 1000);
        grace.mint(address(this), 1000);
        IERC20[] memory duplicateTokens = new IERC20[](2);
        duplicateTokens[0] = IERC20(address(backing));
        duplicateTokens[1] = IERC20(address(backing));
        grace.approve(address(reserve), 1000);
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

    function test_pull() public {
        ERC20 backing = new ERC20();
        backing.mint(address(reserve), 1000);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(backing));
        uint[] memory amounts = new uint[](1);
        amounts[0] = 1000;
        reserve.requestPull(tokens, amounts, address(this));
        assertEq(reserve.getPullRequestTimestamp(), block.timestamp);
        assertEq(reserve.getPullRequestDst(), address(this));
        assertEq(reserve.getPullRequestTokensLength(), 1);
        (address token, uint amount) = reserve.getPullRequestTokens(0);
        assertEq(amount, 1000);
        assertEq(token, address(backing));
        vm.expectRevert("tooSoon");
        reserve.executePull();
        vm.warp(block.timestamp + 30 days + 1);
        reserve.executePull();
        assertEq(backing.balanceOf(address(this)), 1000);
        assertEq(backing.balanceOf(address(reserve)), 0);
        assertEq(reserve.getPullRequestTimestamp(), 0);
        assertEq(reserve.getPullRequestDst(), address(0));
        assertEq(reserve.getPullRequestTokensLength(), 0);
    }

}