// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/RateModel.sol";

contract RateModelTest is Test {

    RateModel public rateModel;
    address public owner = address(1); // mock core

    function setUp() public {
        rateModel = new RateModel(9000, 3 days, 0, 5000, 10000);
    }

    function test_constructor() public {
        assert(rateModel.KINK_BPS() == 9000);
        assert(rateModel.HALF_LIFE() == 3 days);
        assert(rateModel.MIN_RATE() == 0);
        assert(rateModel.KINK_RATE() == 5000);
        assert(rateModel.MAX_RATE() == 10000);

        // constraints
        vm.expectRevert("minRate <= kinkRate <= maxRate");
        new RateModel(9000, 3 days, 1, 0, 0);
        vm.expectRevert("minRate <= kinkRate <= maxRate");
        new RateModel(9000, 3 days, 0, 1, 0);
        vm.expectRevert("minRate <= kinkRate <= maxRate");
        new RateModel(9000, 3 days, 1, 1, 0);
        vm.expectRevert("kinkBps must be <= 10000");
        new RateModel(10001, 3 days, 0, 5000, 10000);
        vm.expectRevert("halfLife must be > 0");
        new RateModel(9000, 0, 0, 5000, 10000);
    }

    function test_getTargetRate() public {
        assertEq(rateModel.getTargetRate(0), 0); // minRate
        assertEq(rateModel.getTargetRate(4500), 2500); // mid min-kink
        assertEq(rateModel.getTargetRate(9000), 5000); // kinkRate
        assertEq(rateModel.getTargetRate(9500), 7500); // mid kink-max
        assertEq(rateModel.getTargetRate(10000), 10000); // maxRate
    }

    function test_getRateBps() public {
        uint HALF_LIFE = 3 days;
        assertEq(rateModel.getRateBps(0, 0, 0), 0);
        vm.warp(block.timestamp + HALF_LIFE);
        assertEq(rateModel.getRateBps(10000, 0, 1), 5000); // 0->100% rate, 1x half life
        assertEq(rateModel.getRateBps(0, 10000, 1), 4999); // 100->0% rate, 1x half life
        assertEq(rateModel.getRateBps(10000, 5000, 1), 7500); // 50->100% rate, 1x half life
        assertEq(rateModel.getRateBps(9000, 10000, 1), 7499); // 100->50% rate, 1x half life
        vm.warp(block.timestamp + (2*HALF_LIFE));
        assertEq(rateModel.getRateBps(10000, 0, 1), 8750); //  0->100% rate, 2x half life
        assertEq(rateModel.getRateBps(0, 10000, 1), 1249); // 100->0% rate, 2x half life
        assertEq(rateModel.getRateBps(10000, 5000, 1), 9375); // 50->100% rate, 2x half life
        assertEq(rateModel.getRateBps(9000, 10000, 1), 5624); // 100->50% rate, 2x half life
    }

}