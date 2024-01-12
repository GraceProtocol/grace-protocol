// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/Core.sol";

contract CoreTest is Test {

    Core public core;

    function setUp() public {
        core = new Core(address(this), address(this), address(this), address(this), address(this), address(this));
    }

    function test_constructor() public {
        assertEq(core.owner(), address(this));
    }

}