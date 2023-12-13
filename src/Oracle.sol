// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

interface IOracleERC20 {
    function decimals() external view returns (uint8);
}

contract Oracle {

    uint constant WEEK = 7 days;
    mapping(address => address) public collateralFeeds;
    mapping(address => address) public poolFeeds;
    mapping(address => uint) public poolFixedPrices;
    mapping (address => mapping(uint => uint)) public weeklyLows; // token => week => price
    mapping (address => mapping(uint => uint)) public weeklyHighs; // token => week => price

    function _setCollateralFeed(address token, address feed) internal { collateralFeeds[token] = feed; }
    function _setPoolFeed(address token, address feed) internal { poolFeeds[token] = feed; }
    function _setPoolFixedPrice(address token, uint price) internal { poolFixedPrices[token] = price; }

    function getNormalizedPrice(address token, address feed) internal view returns (uint normalizedPrice) {
        (,int256 signedPrice,,,) = IChainlinkFeed(feed).latestRoundData();
        uint256 price = signedPrice < 0 ? 0 : uint256(signedPrice);
        uint8 feedDecimals = IChainlinkFeed(feed).decimals();
        uint8 tokenDecimals = IOracleERC20(token).decimals();
        if(feedDecimals + tokenDecimals <= 36) {
            uint8 decimals = 36 - feedDecimals - tokenDecimals;
            normalizedPrice = price * (10 ** decimals);
        } else {
            uint8 decimals = feedDecimals + tokenDecimals - 36;
            normalizedPrice = price / 10 ** decimals;
        }
    }

    function getCappedPrice(uint price, uint totalCollateral, uint capUsd) internal pure returns (uint) {
        if (totalCollateral == 0) return capUsd < price ? capUsd : price;
        uint cappedPrice = capUsd * 1e18 / totalCollateral;
        return cappedPrice < price ? cappedPrice : price;
    }

    function getCollateralPriceMantissa(address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) internal returns (uint256) {
        address feed = collateralFeeds[token];
        if(feed != address(0)) {
            // get normalized price, then cap it
            uint normalizedPrice = getCappedPrice(
                getNormalizedPrice(
                    token,
                    feed
                ),
                totalCollateral,
                capUsd
            );
            // potentially store price as this week's low
            uint week = block.timestamp / WEEK;
            uint weekLow = weeklyLows[token][week];
            if(weekLow == 0 || normalizedPrice < weekLow) {
                weeklyLows[token][week] = normalizedPrice;
                weekLow = normalizedPrice;
                emit RecordWeeklyLow(token, normalizedPrice);
            }
            
            // if collateralFactorBps is 0, return normalizedPrice;
            if(collateralFactorBps == 0) return normalizedPrice;
            // get last week's low
            uint lastWeekLow = weeklyLows[token][week - 1];
            // calculate new borrowing power based on collateral factor
            uint newBorrowingPower = normalizedPrice * collateralFactorBps / 10000;
            uint twoWeekLow = weekLow > lastWeekLow && lastWeekLow > 0 ? lastWeekLow : weekLow;
            if(twoWeekLow > 0 && newBorrowingPower > twoWeekLow) {
                uint dampenedPrice = twoWeekLow * 10000 / collateralFactorBps;
                return dampenedPrice < normalizedPrice ? dampenedPrice: normalizedPrice;
            }
            return normalizedPrice;
        }
        return 0;
    }

    function getDebtPriceMantissa(address token) internal returns (uint256) {
        if(poolFixedPrices[token] > 0) return poolFixedPrices[token];
        address feed = poolFeeds[token];
        if(feed != address(0)) {
            // get normalized price
            uint normalizedPrice = getNormalizedPrice(token, feed);
            // potentially store price as this week's high
            uint week = block.timestamp / WEEK;
            uint weekHigh = weeklyHighs[token][week];
            if(normalizedPrice > weekHigh) {
                weeklyHighs[token][week] = normalizedPrice;
                weekHigh = normalizedPrice;
                emit RecordWeeklyHigh(token, normalizedPrice);
            }
            // get last week's high
            uint lastWeekHigh = weeklyHighs[token][week - 1];
            // find the higher of the two
            uint twoWeekHigh = weekHigh > lastWeekHigh ? weekHigh : lastWeekHigh;
            // if the higher of the two is greater than the normalized price, return the higher of the two
            return twoWeekHigh > normalizedPrice ? twoWeekHigh : normalizedPrice;
        }
        return 0;
    }

    function viewCollateralPriceMantissa(address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) public view returns (uint256) {
        address feed = collateralFeeds[token];
        if(feed != address(0)) {
            // get normalized price, then cap it
            uint normalizedPrice = getCappedPrice(
                getNormalizedPrice(
                    token,
                    feed
                ),
                totalCollateral,
                capUsd
            );
            uint week = block.timestamp / WEEK;
            uint weekLow = weeklyLows[token][week];
            if(weekLow == 0 || normalizedPrice < weekLow) {
                weekLow = normalizedPrice;
            }
            // if collateralFactorBps is 0, return normalizedPrice;
            if(collateralFactorBps == 0) return normalizedPrice;
            // get last week's low
            uint lastWeekLow = weeklyLows[token][week - 1];
            // calculate new borrowing power based on collateral factor
            uint newBorrowingPower = normalizedPrice * collateralFactorBps / 10000;
            uint twoWeekLow = weekLow > lastWeekLow && lastWeekLow > 0 ? lastWeekLow : weekLow;
            if(twoWeekLow > 0 && newBorrowingPower > twoWeekLow) {
                uint dampenedPrice = twoWeekLow * 10000 / collateralFactorBps;
                return dampenedPrice < normalizedPrice ? dampenedPrice: normalizedPrice;
            }
            return normalizedPrice;
        }
        return 0;

    }
    function viewDebtPriceMantissa(address token) public view returns (uint256) {
        if(poolFixedPrices[token] > 0) return poolFixedPrices[token];
        address feed = poolFeeds[token];
        if(feed != address(0)) {
            // get normalized price
            uint normalizedPrice = getNormalizedPrice(token, feed);
            // potentially store price as this week's high
            uint week = block.timestamp / WEEK;
            uint weekHigh = weeklyHighs[token][week];
            if(normalizedPrice > weekHigh) {
                weekHigh = normalizedPrice;
            }
            // get last week's high
            uint lastWeekHigh = weeklyHighs[token][week - 1];
            // find the higher of the two
            uint twoWeekHigh = weekHigh > lastWeekHigh ? weekHigh : lastWeekHigh;
            // if the higher of the two is greater than the normalized price, return the higher of the two
            return twoWeekHigh > normalizedPrice ? twoWeekHigh : normalizedPrice;
        }
        return 0;
    }
    
    event RecordWeeklyLow(address indexed token, uint price);
    event RecordWeeklyHigh(address indexed token, uint price);

}