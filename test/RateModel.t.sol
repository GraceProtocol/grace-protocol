// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/RateModel.sol";

contract RateModelTest is Test {

    RateModel public rateModel;
    address public owner = address(1); // mock core

    function setUp() public {
        rateModel = new RateModel(9000, 0, 5000, 10000);
    }

    function test_constructor() public {
        assert(rateModel.KINK_BPS() == 9000);
        assert(rateModel.MIN_RATE() == 0);
        assert(rateModel.KINK_RATE() == 5000);
        assert(rateModel.MAX_RATE() == 10000);

        // constraints
        vm.expectRevert("minRate <= kinkRate <= maxRate");
        new RateModel(9000, 1, 0, 0);
        vm.expectRevert("minRate <= kinkRate <= maxRate");
        new RateModel(9000, 1, 0, 1);
        vm.expectRevert("minRate <= kinkRate <= maxRate");
        new RateModel(9000, 1, 1, 0);
        vm.expectRevert("kinkBps must be <= 10000");
        new RateModel(10001, 1, 0, 5000);
    }

    function test_getRateBps() public {
        vm.warp(1 days);
        assertEq(rateModel.getRateBps(0, 0, 0), 0);
        assertEq(rateModel.getRateBps(9000, 0, 0), 5000);
        assertEq(rateModel.getRateBps(10000, 0, 0), 10000);
    }
}