// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/RateModel.sol";

contract RateModelTest is Test {

    RateModel public rateModel;
    address public owner = address(1); // mock core

    function setUp() public {
        rateModel = new RateModel(9000, 100, 0, 5000, 10000);
    }

    function test_constructor() public {
        assert(rateModel.KINK_BPS() == 9000);
        assert(rateModel.BPS_PER_DAY() == 100);
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
        vm.expectRevert("bpsPerDay must be > 0");
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
        vm.warp(1 days);
        uint KINK_UTIL = 9000; // 50% rate
        uint LAST_RATE = 10000;
        uint BPS_PER_DAY = rateModel.BPS_PER_DAY();
        // lastAccrued = block.timestamp; should only use last rate
        assertEq(rateModel.getRateBps(0, LAST_RATE, 1 days), LAST_RATE);
        assertEq(rateModel.getRateBps(KINK_UTIL, LAST_RATE, 1 days), LAST_RATE);
        assertEq(rateModel.getRateBps(KINK_UTIL*2, LAST_RATE, 1 days), LAST_RATE);

        // lastAccrued = block.timestamp - 0.5 days; should change by half BPS_PER_DAY
        assertEq(rateModel.getRateBps(0, LAST_RATE, 0.5 days), LAST_RATE - (BPS_PER_DAY/2));
        assertEq(rateModel.getRateBps(KINK_UTIL, LAST_RATE, 0.5 days), LAST_RATE - (BPS_PER_DAY/2));
        assertEq(rateModel.getRateBps(10000, LAST_RATE, 0.5 days), LAST_RATE);
        assertEq(rateModel.getRateBps(KINK_UTIL, 0, 0.5 days), BPS_PER_DAY/2);

        // lastAccrued = block.timestamp - 1 days; should change by BPS_PER_DAY
        assertEq(rateModel.getRateBps(0, LAST_RATE, 0), LAST_RATE - BPS_PER_DAY);
        assertEq(rateModel.getRateBps(KINK_UTIL, LAST_RATE, 0), LAST_RATE - BPS_PER_DAY);
        assertEq(rateModel.getRateBps(10000, LAST_RATE, 0), LAST_RATE);
        assertEq(rateModel.getRateBps(KINK_UTIL, 0, 0), BPS_PER_DAY);

        // lastAccrued = block.timestamp - 2 days; should change by BPS_PER_DAY*2
        vm.warp(2 days);
        assertEq(rateModel.getRateBps(0, LAST_RATE, 0), LAST_RATE - BPS_PER_DAY*2);
        assertEq(rateModel.getRateBps(KINK_UTIL, LAST_RATE, 0), LAST_RATE - (BPS_PER_DAY*2));
        assertEq(rateModel.getRateBps(10000, LAST_RATE, 0), LAST_RATE);
        assertEq(rateModel.getRateBps(KINK_UTIL, 0, 0), BPS_PER_DAY*2);

        // lastAccrued = a lot of days; should change up to curveRate
        vm.warp(10000 days);
        assertEq(rateModel.getRateBps(0, LAST_RATE, 0), 0);
        assertEq(rateModel.getRateBps(KINK_UTIL, LAST_RATE, 0), 5000);
        assertEq(rateModel.getRateBps(10000, 0, 0), 10000);
    }

}