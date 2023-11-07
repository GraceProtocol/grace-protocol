// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/RateModel.sol";

contract RateModelTest is Test {

    RateModel public rateModel;
    address public owner = address(1); // mock core

    function setUp() public {
        rateModel = new RateModel(address(this));
    }

    function test_constructor() public {
        assertEq(rateModel.core(), address(this));
    }

    function test_setTargetRates() public {
        // only core owner
        vm.expectRevert("onlyCoreOwner");
        rateModel.setTargetRates(address(2), 0, 0, 0);

        // invalid rates
        vm.startPrank(owner);
        vm.expectRevert("invalidRates");
        rateModel.setTargetRates(address(2), 1, 0, 0);
        vm.expectRevert("invalidRates");
        rateModel.setTargetRates(address(2), 0, 1, 0);
        vm.expectRevert("invalidRates");
        rateModel.setTargetRates(address(2), 1, 1, 0);

        // success case
        rateModel.setTargetRates(address(2), 0, 1, 2);
    }

    function test_getCurveRate() public {
        assertEq(rateModel.getCurveRate(address(2), 10000), 0);
        vm.startPrank(owner);
        rateModel.setTargetRates(address(2), 0, 5000, 10000); // 0%, 50%, 100%
        assertEq(rateModel.getCurveRate(address(2), 0), 0); // minRate
        assertEq(rateModel.getCurveRate(address(2), 4500), 2500); // mid min-kink
        assertEq(rateModel.getCurveRate(address(2), 9000), 5000); // kinkRate
        assertEq(rateModel.getCurveRate(address(2), 9500), 7500); // mid kink-max
        assertEq(rateModel.getCurveRate(address(2), 10000), 10000); // maxRate
    }

    function test_getRateBps() public {
        uint HALF_LIFE = 3 days;
        vm.startPrank(owner);
        rateModel.setTargetRates(address(2), 0, 5000, 10000); // 0%, 50%, 100%
        assertEq(rateModel.getRateBps(address(2), 0, 0, 0), 0);
        vm.warp(block.timestamp + HALF_LIFE);
        assertEq(rateModel.getRateBps(address(2), 10000, 0, 1), 5000); // 0->100% rate, 1x half life
        assertEq(rateModel.getRateBps(address(2), 0, 10000, 1), 4999); // 100->0% rate, 1x half life
        assertEq(rateModel.getRateBps(address(2), 10000, 5000, 1), 7500); // 50->100% rate, 1x half life
        assertEq(rateModel.getRateBps(address(2), 9000, 10000, 1), 7499); // 100->50% rate, 1x half life
        vm.warp(block.timestamp + (2*HALF_LIFE));
        assertEq(rateModel.getRateBps(address(2), 10000, 0, 1), 8750); //  0->100% rate, 2x half life
        assertEq(rateModel.getRateBps(address(2), 0, 10000, 1), 1249); // 100->0% rate, 2x half life
        assertEq(rateModel.getRateBps(address(2), 10000, 5000, 1), 9375); // 50->100% rate, 2x half life
        assertEq(rateModel.getRateBps(address(2), 9000, 10000, 1), 5624); // 100->50% rate, 2x half life
    }

}