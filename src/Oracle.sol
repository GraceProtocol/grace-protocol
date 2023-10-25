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

    address public immutable core;
    mapping(address => address) public collateralFeeds;
    mapping(address => address) public poolFeeds;
    mapping (address => mapping(uint => uint)) public dailyLows; // token => day => price
    mapping (address => mapping(uint => uint)) public dailyHighs; // token => day => price

    constructor() {
        core = msg.sender;
    }

    modifier onlyCore {
        require(msg.sender == core, "onlyCore");
        _;
    }

    function setCollateralFeed(address token, address feed) onlyCore external { collateralFeeds[token] = feed; }
    function setPoolFeed(address token, address feed) onlyCore external { poolFeeds[token] = feed; }

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

    function getCappedPrice(uint price, uint8 decimals, uint totalCollateral, uint capUsd) internal pure returns (uint) {
        if (totalCollateral == 0) return price;
        uint cappedPrice = capUsd * 10 ** decimals / totalCollateral;
        return cappedPrice < price ? cappedPrice : price;
    }

    function getCollateralPriceMantissa(address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) external onlyCore returns (uint256) {
        address feed = collateralFeeds[token];
        if(feed != address(0)) {
            // get normalized price, then cap it
            uint normalizedPrice = getCappedPrice(
                getNormalizedPrice(
                    token,
                    feed
                ),
                IOracleERC20(token).decimals(),
                totalCollateral,
                capUsd
            );
            // potentially store price as today's low
            uint day = block.timestamp / 1 days;
            uint todaysLow = dailyLows[token][day];
            if(todaysLow == 0 || normalizedPrice < todaysLow) {
                dailyLows[token][day] = normalizedPrice;
                todaysLow = normalizedPrice;
                emit RecordDailyLow(token, normalizedPrice);
            }
            
            // if collateralFactorBps is 0, return normalizedPrice;
            if(collateralFactorBps == 0) return normalizedPrice;
            // get yesterday's low
            uint yesterdaysLow = dailyLows[token][day - 1];
            // calculate new borrowing power based on collateral factor
            uint newBorrowingPower = normalizedPrice * collateralFactorBps / 10000;
            uint twoDayLow = todaysLow > yesterdaysLow && yesterdaysLow > 0 ? yesterdaysLow : todaysLow;
            if(twoDayLow > 0 && newBorrowingPower > twoDayLow) {
                uint dampenedPrice = twoDayLow * 10000 / collateralFactorBps;
                return dampenedPrice < normalizedPrice ? dampenedPrice: normalizedPrice;
            }
            return normalizedPrice;
        }
        return 0;
    }

    function getDebtPriceMantissa(address token) external onlyCore returns (uint256) {
        address feed = poolFeeds[token];
        if(feed != address(0)) {
            // get normalized price
            uint normalizedPrice = getNormalizedPrice(token, feed);
            // potentially store price as today's high
            uint day = block.timestamp / 1 days;
            uint todaysHigh = dailyHighs[token][day];
            if(normalizedPrice > todaysHigh) {
                dailyHighs[token][day] = normalizedPrice;
                todaysHigh = normalizedPrice;
                emit RecordDailyHigh(token, normalizedPrice);
            }
            // get yesterday's high
            uint yesterdaysHigh = dailyHighs[token][day - 1];
            // find the higher of the two
            uint twoDayHigh = todaysHigh > yesterdaysHigh ? todaysHigh : yesterdaysHigh;
            // if the higher of the two is greater than the normalized price, return the higher of the two
            return twoDayHigh > normalizedPrice ? twoDayHigh : normalizedPrice;
        }
        return 0;
    }

    /// TODO: implement these functions
    function viewCollateralPriceMantissa(address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) external view returns (uint256) {
        address feed = collateralFeeds[token];
        if(feed != address(0)) {
            // get normalized price, then cap it
            uint normalizedPrice = getCappedPrice(
                getNormalizedPrice(
                    token,
                    feed
                ),
                IOracleERC20(token).decimals(),
                totalCollateral,
                capUsd
            );
            uint day = block.timestamp / 1 days;
            uint todaysLow = dailyLows[token][day];
            if(todaysLow == 0 || normalizedPrice < todaysLow) {
                todaysLow = normalizedPrice;
            }
            // if collateralFactorBps is 0, return normalizedPrice;
            if(collateralFactorBps == 0) return normalizedPrice;
            // get yesterday's low
            uint yesterdaysLow = dailyLows[token][day - 1];
            // calculate new borrowing power based on collateral factor
            uint newBorrowingPower = normalizedPrice * collateralFactorBps / 10000;
            uint twoDayLow = todaysLow > yesterdaysLow && yesterdaysLow > 0 ? yesterdaysLow : todaysLow;
            if(twoDayLow > 0 && newBorrowingPower > twoDayLow) {
                uint dampenedPrice = twoDayLow * 10000 / collateralFactorBps;
                return dampenedPrice < normalizedPrice ? dampenedPrice: normalizedPrice;
            }
            return normalizedPrice;
        }
        return 0;

    }
    function viewDebtPriceMantissa(address token) external view returns (uint256) {
        address feed = poolFeeds[token];
        if(feed != address(0)) {
            // get normalized price
            uint normalizedPrice = getNormalizedPrice(token, feed);
            // potentially store price as today's high
            uint day = block.timestamp / 1 days;
            uint todaysHigh = dailyHighs[token][day];
            if(normalizedPrice > todaysHigh) {
                todaysHigh = normalizedPrice;
            }
            // get yesterday's high
            uint yesterdaysHigh = dailyHighs[token][day - 1];
            // find the higher of the two
            uint twoDayHigh = todaysHigh > yesterdaysHigh ? todaysHigh : yesterdaysHigh;
            // if the higher of the two is greater than the normalized price, return the higher of the two
            return twoDayHigh > normalizedPrice ? twoDayHigh : normalizedPrice;
        }
        return 0;
    }
    
    event RecordDailyLow(address indexed token, uint price);
    event RecordDailyHigh(address indexed token, uint price);

}