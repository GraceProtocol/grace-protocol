// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

contract FixedPriceFeed {

    uint8 public immutable _decimals;
    int public immutable _signedPrice;

    constructor(uint8 decimals_, int signedPrice_) {
        _decimals = decimals_;
        _signedPrice = signedPrice_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _signedPrice, 0, 0, 0);
    }
}