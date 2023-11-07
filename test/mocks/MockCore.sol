// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

contract MockCore {

    function globalLock(address) external {}
    function globalUnlock() external {}
    function updateCollateralFeeController() external {}
    function getCollateralFeeBps(address) external view returns (uint, address) {
        return (10000, address(1));
    }
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
    function onPoolWithdraw(uint256 amount) external returns (bool) {
        return true;
    }
    function updateInterestRateController() external {}
    function getBorrowRateBps(address,uint,uint,uint) external view returns (uint) {
        return 10000;
    }
    function onPoolBorrow(address, uint) external returns (bool) {
        return true;
    }
    function onPoolRepay(address, uint) external returns (bool) {
        return true;
    }
    function feeDestination() external view returns (address) {
        return address(1);
    }
}