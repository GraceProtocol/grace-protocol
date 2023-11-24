// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/Oracle.sol";
import "./mocks/FixedPriceFeed.sol";
import "./mocks/ERC20.sol";

contract OracleTest is Test, Oracle {

    Oracle public oracle;
    address UNAUTHORIZED = address(1);

    function setUp() public {
        oracle = new Oracle();
    }

    function test_constructor() public {
        assertEq(oracle.core(), address(this));
    }

    function test_setPoolFixedPrice() public {
        // success case
        oracle.setPoolFixedPrice(address(2), 1e18);
        assertEq(oracle.poolFixedPrices(address(2)), 1e18);
        assertEq(oracle.viewDebtPriceMantissa(address(2)), 1e18);
        assertEq(oracle.getDebtPriceMantissa(address(2)), 1e18);

        // only core
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert("onlyCore");
        oracle.setPoolFixedPrice(address(2), 1e18);
    }
 
    function test_setCollateralFeed() public {
        // success case
        oracle.setCollateralFeed(address(2), address(3));
        assertEq(oracle.collateralFeeds(address(2)), address(3));

        // only core
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert("onlyCore");
        oracle.setCollateralFeed(address(2), address(3));
    }

    function test_setPoolFeed() public {
        // success case
        oracle.setPoolFeed(address(2), address(3));
        assertEq(oracle.poolFeeds(address(2)), address(3));

        // only core
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert("onlyCore");
        oracle.setPoolFeed(address(2), address(3));
    }

    function test_getNormalizedPrice() public {
        ERC20 token = new ERC20();
        // 18 decimal feed, 18 decimal token
        address feed = address(new FixedPriceFeed(18, 1e18));
        assertEq(getNormalizedPrice(address(token), feed), 1e18);
        // 18 decimal feed, 6 decimal token
        feed = address(new FixedPriceFeed(18, 1e18));
        token.setDecimals(6);
        assertEq(getNormalizedPrice(address(token), feed), 10 ** (36 - 6));
        // 6 decimal feed, 18 decimal token
        feed = address(new FixedPriceFeed(6, 1e6));
        token.setDecimals(18);
        assertEq(getNormalizedPrice(address(token), feed), 1e18);
        // 6 decimal feed, 6 decimal token
        feed = address(new FixedPriceFeed(6, 1e6));
        token.setDecimals(6);
        assertEq(getNormalizedPrice(address(token), feed),  10 ** (36 - 6));
        // 0 decimal feed, 18 decimal token
        feed = address(new FixedPriceFeed(0, 1));
        token.setDecimals(18);
        assertEq(getNormalizedPrice(address(token), feed), 1e18);
        // 18 decimal feed, 0 decimal token
        feed = address(new FixedPriceFeed(18, 1e18));
        token.setDecimals(0);
        assertEq(getNormalizedPrice(address(token), feed), 1e36);
    }

    function test_getCappedPrice() public {
        // 0 totalCollateral
        assertEq(getCappedPrice(1e18, 0, 1e18), 1e18);
        // cap higher than price
        assertEq(getCappedPrice(1e18, 1e18, 2e18), 1e18);
        // cap lower than price
        assertEq(getCappedPrice(2e18, 1e18, 1e18), 1e18);
        // cap higher than price, 6 decimals
        assertEq(getCappedPrice(10 ** (36 - 6), 1e6, 2e18), 10 ** (36 - 6));
        // cap lower than price, 6 decimals
        assertEq(getCappedPrice(2 * 10 ** (36 - 6), 1e6, 1e18), 10 ** (36 - 6));
        // cap higher than price, 0 decimals
        assertEq(getCappedPrice(10 ** 36, 1, 2e18), 10 ** 36);
        // cap lower than price, 0 decimals
        assertEq(getCappedPrice(2 * 10 ** 36, 1, 1e18), 10 ** 36);
    }

    function test_getCollateralPriceMantissa() public {
        ERC20 token = new ERC20();
        collateralFeeds[address(token)] = address(new FixedPriceFeed(18, 1e18));
        vm.warp(block.timestamp + WEEK);
        uint CF = 5000;
        uint cap = 1e18;
        uint totalCollateral = 1e18;
        vm.startPrank(address(msg.sender)); // core
        // first record
        assertEq(Oracle(address(this)).getCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 1e18);
        assertEq(weeklyLows[address(token)][block.timestamp / WEEK], 1e18);
        assertEq(Oracle(address(this)).viewCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 1e18);
        // second record, triple price, triple cap. Triggers PPO
        cap *= 3;
        collateralFeeds[address(token)] = address(new FixedPriceFeed(18, 3 * 1e18));
        assertEq(Oracle(address(this)).getCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 2e18);
        assertEq(weeklyLows[address(token)][block.timestamp / WEEK], 1e18);
        assertEq(Oracle(address(this)).viewCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 2e18);
        // week 2, PPO still active
        vm.warp(block.timestamp + WEEK);
        assertEq(weeklyLows[address(token)][block.timestamp / WEEK], 0);
        assertEq(weeklyLows[address(token)][block.timestamp / WEEK - 1], 1e18);
        assertEq(Oracle(address(this)).getCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 2e18);
        assertEq(Oracle(address(this)).viewCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 2e18);
        // week 3, PPO inactive
        vm.warp(block.timestamp + WEEK);
        assertEq(weeklyLows[address(token)][block.timestamp / WEEK], 0);
        assertEq(weeklyLows[address(token)][block.timestamp / WEEK - 1], 3e18);
        assertEq(Oracle(address(this)).getCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 3e18);
        assertEq(Oracle(address(this)).viewCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 3e18);
    }

    function test_getDebtPriceMantissa() public {
        ERC20 token = new ERC20();
        poolFeeds[address(token)] = address(new FixedPriceFeed(18, 1e18));
        vm.warp(block.timestamp + WEEK);
        vm.startPrank(address(msg.sender)); // core
        // first record
        assertEq(Oracle(address(this)).getDebtPriceMantissa(address(token)), 1e18);
        assertEq(weeklyHighs[address(token)][block.timestamp / WEEK], 1e18);
        assertEq(Oracle(address(this)).viewDebtPriceMantissa(address(token)), 1e18);
        // second record, reduce price by 90%
        poolFeeds[address(token)] = address(new FixedPriceFeed(18, 1e17));
        assertEq(Oracle(address(this)).getDebtPriceMantissa(address(token)), 1e18);
        assertEq(weeklyHighs[address(token)][block.timestamp / WEEK], 1e18);
        assertEq(Oracle(address(this)).viewDebtPriceMantissa(address(token)), 1e18);
        // week 2, PPO still active
        vm.warp(block.timestamp + WEEK);
        assertEq(weeklyHighs[address(token)][block.timestamp / WEEK], 0);
        assertEq(weeklyHighs[address(token)][block.timestamp / WEEK - 1], 1e18);
        assertEq(Oracle(address(this)).getDebtPriceMantissa(address(token)), 1e18);
        assertEq(Oracle(address(this)).viewDebtPriceMantissa(address(token)), 1e18);
        // week 3, PPO inactive
        vm.warp(block.timestamp + WEEK);
        assertEq(weeklyHighs[address(token)][block.timestamp / WEEK], 0);
        assertEq(weeklyHighs[address(token)][block.timestamp / WEEK - 1], 1e17);
        assertEq(Oracle(address(this)).getDebtPriceMantissa(address(token)), 1e17);
        assertEq(Oracle(address(this)).viewDebtPriceMantissa(address(token)), 1e17);
    }

}