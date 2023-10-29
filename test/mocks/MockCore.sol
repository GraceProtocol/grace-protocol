// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

contract MockCore {

    function globalLock(address) external {}
    function globalUnlock() external {}
    function updateCollateralFeeController() external {}
    function getCollateralFeeBps(address) external view returns (uint, address) {}
    function onCollateralDeposit(address, uint) external returns (bool) {
        return true;
    }
    function onCollateralWithdraw(address, uint) external returns (bool) {
        return true;
    }
    function onCollateralReceive(address) external returns (bool) {
        return true;
    }
    function onPoolDeposit(uint) external returns (bool) {
        return true;
    }
    function updateInterestRateController() external {}
    function getBorrowRateBps(address) external view returns (uint, address) {}
    function onPoolBorrow(address, uint) external returns (bool) {
        return true;
    }
    function onPoolRepay(address, uint) external returns (bool) {
        return true;
    }
}