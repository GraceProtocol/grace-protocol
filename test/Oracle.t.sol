// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

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
        assertEq(oracle.owner(), address(this));
    }

    function test_setPoolFixedPrice() public {
        // success case
        oracle.setPoolFixedPrice(address(2), 1e18);
        assertEq(oracle.poolFixedPrices(address(2)), 1e18);
        assertEq(oracle.viewDebtPriceMantissa(address(this), address(2)), 1e18);
        assertEq(oracle.getDebtPriceMantissa(address(2)), 1e18);

        // only owner
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert("onlyOwner");
        oracle.setPoolFixedPrice(address(2), 1e18);
    }
 
    function test_setCollateralFeed() public {
        // success case
        oracle.setCollateralFeed(address(2), address(3));
        assertEq(oracle.collateralFeeds(address(2)), address(3));

        // only owner
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert("onlyOwner");
        oracle.setCollateralFeed(address(2), address(3));
    }

    function test_setPoolFeed() public {
        // success case
        oracle.setPoolFeed(address(2), address(3));
        assertEq(oracle.poolFeeds(address(2)), address(3));

        // only owner
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert("onlyOwner");
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
        oracle.setCollateralFeed(address(token), address(new FixedPriceFeed(18, 1e18)));
        uint WEEK = 7 days;
        skip(WEEK);
        uint CF = 5000;
        uint cap = 1e18;
        uint totalCollateral = 1e18;
        // first record
        assertEq(oracle.getCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 1e18);
        assertEq(oracle.getCollateralLow(address(this), address(token)), 1e18);
        assertEq(oracle.viewCollateralPriceMantissa(address(this), address(token), CF, totalCollateral, cap), 1e18);
        // second record, triple price, triple cap. Triggers PPO
        cap *= 3;
        oracle.setCollateralFeed(address(token), address(new FixedPriceFeed(18, 3*1e18)));
        assertEq(oracle.getCollateralLow(address(this), address(token)), 1e18);
        assertEq(oracle.getCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 2e18);
        assertEq(oracle.viewCollateralPriceMantissa(address(this), address(token), CF, totalCollateral, cap), 2e18);
        // week 2, price low rises by 10%
        skip(WEEK);
        assertEq(oracle.getCollateralLow(address(this), address(token)), 1e18 + 1e17);
        assertEq(oracle.getCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 2e18 + 2e17);
        assertEq(oracle.viewCollateralPriceMantissa(address(this), address(token), CF, totalCollateral, cap), 2e18 + 2e17);
        // week 3, drop price by 10x
        skip(WEEK);
        oracle.setCollateralFeed(address(token), address(new FixedPriceFeed(18, 1e17)));
        assertEq(oracle.getCollateralLow(address(this), address(token)), 1e17);
        assertEq(oracle.getCollateralPriceMantissa(address(token), CF, totalCollateral, cap), 1e17);
        assertEq(oracle.viewCollateralPriceMantissa(address(this), address(token), CF, totalCollateral, cap), 1e17);

    }

    function test_getDebtPriceMantissa() public {
        ERC20 token = new ERC20();
        oracle.setPoolFeed(address(token), address(new FixedPriceFeed(18, 1e18)));
        uint WEEK = 7 days;
        skip(WEEK);
        // first record
        assertEq(oracle.getDebtPriceMantissa(address(token)), 1e18);
        assertEq(oracle.getPoolHigh(address(this), address(token)), 1e18);
        assertEq(oracle.viewDebtPriceMantissa(address(this), address(token)), 1e18);
        // second record, reduce price by 90%
        oracle.setPoolFeed(address(token), address(new FixedPriceFeed(18, 1e17)));
        assertEq(oracle.getDebtPriceMantissa(address(token)), 1e18);
        assertEq(oracle.getPoolHigh(address(this), address(token)), 1e18);
        assertEq(oracle.viewDebtPriceMantissa(address(this), address(token)), 1e18);
        // week 2, price high drops by 10%
        skip(WEEK);
        assertEq(oracle.getPoolHigh(address(this), address(token)), 1e18 - 1e17);
        assertEq(oracle.getDebtPriceMantissa(address(token)), 1e18 - 1e17);
        assertEq(oracle.viewDebtPriceMantissa(address(this), address(token)), 1e18 - 1e17);
        // week 3, 10x price
        skip(WEEK);
        oracle.setPoolFeed(address(token), address(new FixedPriceFeed(18, 1e19)));
        assertEq(oracle.getPoolHigh(address(this), address(token)), 1e19);
        assertEq(oracle.getDebtPriceMantissa(address(token)), 1e19);
        assertEq(oracle.viewDebtPriceMantissa(address(this), address(token)), 1e19);
    }

}