// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/Oracle.sol";
import "./mocks/FixedPriceFeed.sol";
import "./mocks/ERC20.sol";

contract OracleHandler is Oracle {
    function setCollateralFeed(address token, address feed) public {
        collateralFeeds[token] = feed;
    }
    function setPoolFeed(address token, address feed) public {
        poolFeeds[token] = feed;
    }
    function setPoolFixedPrice(address token, uint price) public {
        poolFixedPrices[token] = price;
    }
    function getDebtPriceMantissaPublic(address token) public returns (uint) {
        return getDebtPriceMantissa(token);
    }
    function getCollateralPriceMantissaPublic(address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) public returns (uint) {
        return getCollateralPriceMantissa(token, collateralFactorBps, totalCollateral, capUsd);
    }
    function getNormalizedPricePublic(address token, address feed) public view returns (uint) {
        return getNormalizedPrice(token, feed);
    }
    function getCappedPricePublic(uint price, uint totalCollateral, uint capUsd) public pure returns (uint) {
        return getCappedPrice(price, totalCollateral, capUsd);
    }
}

contract OracleTest is Test {

    OracleHandler public oracleHandler;

    function setUp() public {
        oracleHandler = new OracleHandler();
    }

    function test_setPoolFixedPrice() public {
        oracleHandler.setPoolFixedPrice(address(2), 1e18);
        assertEq(oracleHandler.poolFixedPrices(address(2)), 1e18);
        assertEq(oracleHandler.viewDebtPriceMantissa(address(2)), 1e18);
        assertEq(oracleHandler.getDebtPriceMantissaPublic(address(2)), 1e18);
    }
 
    function test_setCollateralFeed() public {
        oracleHandler.setCollateralFeed(address(2), address(3));
        assertEq(oracleHandler.collateralFeeds(address(2)), address(3));
    }

    function test_setPoolFeed() public {
        oracleHandler.setPoolFeed(address(2), address(3));
        assertEq(oracleHandler.poolFeeds(address(2)), address(3));
    }

    function test_getNormalizedPrice() public {
        ERC20 token = new ERC20();
        // 18 decimal feed, 18 decimal token
        address feed = address(new FixedPriceFeed(18, 1e18));
        assertEq(oracleHandler.getNormalizedPricePublic(address(token), feed), 1e18);
        // 18 decimal feed, 6 decimal token
        feed = address(new FixedPriceFeed(18, 1e18));
        token.setDecimals(6);
        assertEq(oracleHandler.getNormalizedPricePublic(address(token), feed), 10 ** (36 - 6));
        // 6 decimal feed, 18 decimal token
        feed = address(new FixedPriceFeed(6, 1e6));
        token.setDecimals(18);
        assertEq(oracleHandler.getNormalizedPricePublic(address(token), feed), 1e18);
        // 6 decimal feed, 6 decimal token
        feed = address(new FixedPriceFeed(6, 1e6));
        token.setDecimals(6);
        assertEq(oracleHandler.getNormalizedPricePublic(address(token), feed),  10 ** (36 - 6));
        // 0 decimal feed, 18 decimal token
        feed = address(new FixedPriceFeed(0, 1));
        token.setDecimals(18);
        assertEq(oracleHandler.getNormalizedPricePublic(address(token), feed), 1e18);
        // 18 decimal feed, 0 decimal token
        feed = address(new FixedPriceFeed(18, 1e18));
        token.setDecimals(0);
        assertEq(oracleHandler.getNormalizedPricePublic(address(token), feed), 1e36);
    }

    function test_getCappedPrice() public {
        // 0 totalCollateral
        assertEq(oracleHandler.getCappedPricePublic(1e18, 0, 1e18), 1e18);
        // cap higher than price
        assertEq(oracleHandler.getCappedPricePublic(1e18, 1e18, 2e18), 1e18);
        // cap lower than price
        assertEq(oracleHandler.getCappedPricePublic(2e18, 1e18, 1e18), 1e18);
        // cap higher than price, 6 decimals
        assertEq(oracleHandler.getCappedPricePublic(10 ** (36 - 6), 1e6, 2e18), 10 ** (36 - 6));
        // cap lower than price, 6 decimals
        assertEq(oracleHandler.getCappedPricePublic(2 * 10 ** (36 - 6), 1e6, 1e18), 10 ** (36 - 6));
        // cap higher than price, 0 decimals
        assertEq(oracleHandler.getCappedPricePublic(10 ** 36, 1, 2e18), 10 ** 36);
        // cap lower than price, 0 decimals
        assertEq(oracleHandler.getCappedPricePublic(2 * 10 ** 36, 1, 1e18), 10 ** 36);
    }

    function test_getCollateralPriceMantissa() public {
        uint WEEK = 7 days;
        ERC20 token = new ERC20();
        oracleHandler.setCollateralFeed(address(token), address(new FixedPriceFeed(18, 1e18)));
        vm.warp(block.timestamp + WEEK);
        uint CF = 5000;
        uint cap = 1e18;
        uint totalCollateral = 1e18;
        vm.startPrank(address(msg.sender)); // core
        // first record
        assertEq(oracleHandler.getCollateralPriceMantissaPublic(address(token), CF, totalCollateral, cap), 1e18);
        assertEq(oracleHandler.weeklyLows(address(token),block.timestamp / WEEK), 1e18);
        assertEq(oracleHandler.viewCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 1e18);
        // second record, triple price, triple cap. Triggers PPO
        cap *= 3;
        oracleHandler.setCollateralFeed(address(token), address(new FixedPriceFeed(18, 3 * 1e18)));
        assertEq(oracleHandler.getCollateralPriceMantissaPublic(address(token), CF, totalCollateral, cap), 2e18);
        assertEq(oracleHandler.weeklyLows(address(token), block.timestamp / WEEK), 1e18);
        assertEq(oracleHandler.viewCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 2e18);
        // week 2, PPO still active
        vm.warp(block.timestamp + WEEK);
        assertEq(oracleHandler.weeklyLows(address(token),block.timestamp / WEEK), 0);
        assertEq(oracleHandler.weeklyLows(address(token), block.timestamp / WEEK - 1), 1e18);
        assertEq(oracleHandler.getCollateralPriceMantissaPublic(address(token), CF, totalCollateral, cap), 2e18);
        assertEq(oracleHandler.viewCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 2e18);
        // week 3, PPO inactive
        vm.warp(block.timestamp + WEEK);
        assertEq(oracleHandler.weeklyLows(address(token), block.timestamp / WEEK), 0);
        assertEq(oracleHandler.weeklyLows(address(token), block.timestamp / WEEK - 1), 3e18);
        assertEq(oracleHandler.getCollateralPriceMantissaPublic(address(token), CF, totalCollateral, cap), 3e18);
        assertEq(oracleHandler.viewCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 3e18);
    }

    function test_getDebtPriceMantissa() public {
        uint WEEK = 7 days;
        ERC20 token = new ERC20();
        oracleHandler.setPoolFeed(address(token), address(new FixedPriceFeed(18, 1e18)));
        vm.warp(block.timestamp + WEEK);
        vm.startPrank(address(msg.sender)); // core
        // first record
        assertEq(oracleHandler.getDebtPriceMantissaPublic(address(token)), 1e18);
        assertEq(oracleHandler.weeklyHighs(address(token), block.timestamp / WEEK), 1e18);
        assertEq(oracleHandler.viewDebtPriceMantissa(address(token)), 1e18);
        // second record, reduce price by 90%
        oracleHandler.setPoolFeed(address(token), address(new FixedPriceFeed(18, 1e17)));
        assertEq(oracleHandler.getDebtPriceMantissaPublic(address(token)), 1e18);
        assertEq(oracleHandler.weeklyHighs(address(token), block.timestamp / WEEK), 1e18);
        assertEq(oracleHandler.viewDebtPriceMantissa(address(token)), 1e18);
        // week 2, PPO still active
        vm.warp(block.timestamp + WEEK);
        assertEq(oracleHandler.weeklyHighs(address(token), block.timestamp / WEEK), 0);
        assertEq(oracleHandler.weeklyHighs(address(token), block.timestamp / WEEK - 1), 1e18);
        assertEq(oracleHandler.getDebtPriceMantissaPublic(address(token)), 1e18);
        assertEq(oracleHandler.viewDebtPriceMantissa(address(token)), 1e18);
        // week 3, PPO inactive
        vm.warp(block.timestamp + WEEK);
        assertEq(oracleHandler.weeklyHighs(address(token), block.timestamp / WEEK), 0);
        assertEq(oracleHandler.weeklyHighs(address(token), block.timestamp / WEEK - 1), 1e17);
        assertEq(oracleHandler.getDebtPriceMantissaPublic(address(token)), 1e17);
        assertEq(oracleHandler.viewDebtPriceMantissa(address(token)), 1e17);
    }
}