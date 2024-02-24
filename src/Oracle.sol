// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

interface IOracleERC20 {
    function decimals() external view returns (uint8);
}

contract Oracle {

    struct PriceLog {
        uint price;
        uint timestamp;
    }

    address public owner;
    uint constant WEEK = 7 days;
    uint public bpsPerWeek = 1000;
    mapping(address => address) public collateralFeeds;
    mapping(address => address) public poolFeeds;
    mapping(address => uint) public poolFixedPrices;
    mapping (address => mapping(address => PriceLog)) public collateralLows; // caller => underlying => price
    mapping (address => mapping(address => PriceLog)) public poolHighs; // caller => underlying => price

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    function setOwner(address _owner) external onlyOwner { owner = _owner; }
    function setCollateralFeed(address token, address feed) onlyOwner external { collateralFeeds[token] = feed; }
    function setPoolFeed(address token, address feed) onlyOwner external { poolFeeds[token] = feed; }
    function setPoolFixedPrice(address token, uint price) onlyOwner external { poolFixedPrices[token] = price; }
    function setBpsPerWeek(uint _bpsPerWeek) onlyOwner external { bpsPerWeek = _bpsPerWeek; }

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

    function getCollateralLow(address caller, address token) public view returns (uint){
        uint price = getNormalizedPrice(token, collateralFeeds[token]);
        PriceLog storage low = collateralLows[caller][token];
        if(low.price == 0 || price < low.price) {
            return price;
        } else {
            uint change = low.price * (block.timestamp - low.timestamp) * bpsPerWeek / 10000 / WEEK;
            if (change > low.price * bpsPerWeek / 10000) change = low.price * bpsPerWeek / 10000; // cap change per update to bpsPerWeek
            if(price < low.price + change) {
                return price;
            } else {
                return low.price + change;
            }
        }
    }

    function getPoolHigh(address caller, address token) public view returns (uint){
        uint price = getNormalizedPrice(token, poolFeeds[token]);
        PriceLog storage high = poolHighs[caller][token];
        if(price > high.price) {
            return price;
        } else {
            uint change = high.price * (block.timestamp - high.timestamp) * bpsPerWeek / 10000 / WEEK;
            if (change > high.price * bpsPerWeek / 10000) change = high.price * bpsPerWeek / 10000; // cap change per update to bpsPerWeek
            if (change > high.price) change = high.price; // integer overflow protection
            if(price > high.price - change) {
                return price;
            } else {
                return high.price - change;
            }
        }
    }

    function getCollateralPriceMantissa(address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) external returns (uint256) {
        address feed = collateralFeeds[token];
        if(feed != address(0)) {
            uint low = getCollateralLow(msg.sender, token);
            if(low != collateralLows[msg.sender][token].price) {
                collateralLows[msg.sender][token] = PriceLog(low, block.timestamp);
                emit RecordCollateralLow(msg.sender, token, low);
            }
            uint normalizedPrice = getNormalizedPrice(token, feed);
            // if collateralFactorBps is 0, return capped normalizedPrice;
            if(collateralFactorBps == 0) return getCappedPrice(normalizedPrice, totalCollateral, capUsd);
            // calculate new borrowing power based on collateral factor
            uint newBorrowingPower = normalizedPrice * collateralFactorBps / 10000;
            if(low > 0 && newBorrowingPower > low) {
                uint dampenedPrice = low * 10000 / collateralFactorBps;
                uint unCappedPrice = dampenedPrice < normalizedPrice ? dampenedPrice: normalizedPrice;
                return getCappedPrice(unCappedPrice, totalCollateral, capUsd);
            }
            return getCappedPrice(normalizedPrice, totalCollateral, capUsd);
        }
        return 0;
    }

    function getDebtPriceMantissa(address token) external returns (uint256) {
        if(poolFixedPrices[token] > 0) return poolFixedPrices[token];
        address feed = poolFeeds[token];
        if(feed != address(0)) {
            uint high = getPoolHigh(msg.sender, token);
            if(high != poolHighs[msg.sender][token].price) {
                poolHighs[msg.sender][token] = PriceLog(high, block.timestamp);
                emit RecordPoolHigh(msg.sender, token, high);
            }
            return high;
        }
        return 0;
    }

    function viewCollateralPriceMantissa(address caller, address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) public view returns (uint256) {
        address feed = collateralFeeds[token];
        if(feed != address(0)) {
            uint low = getCollateralLow(caller, token);
            uint normalizedPrice = getNormalizedPrice(token, feed);
            // if collateralFactorBps is 0, return capped normalizedPrice;
            if(collateralFactorBps == 0) return getCappedPrice(normalizedPrice, totalCollateral, capUsd);
            // calculate new borrowing power based on collateral factor
            uint newBorrowingPower = normalizedPrice * collateralFactorBps / 10000;
            if(low > 0 && newBorrowingPower > low) {
                uint dampenedPrice = low * 10000 / collateralFactorBps;
                uint unCappedPrice = dampenedPrice < normalizedPrice ? dampenedPrice: normalizedPrice;
                return getCappedPrice(unCappedPrice, totalCollateral, capUsd);
            }
            return getCappedPrice(normalizedPrice, totalCollateral, capUsd);
        }
        return 0;
    }

    function viewDebtPriceMantissa(address caller, address token) public view returns (uint256) {
        if(poolFixedPrices[token] > 0) return poolFixedPrices[token];
        address feed = poolFeeds[token];
        if(feed != address(0)) {
            return getPoolHigh(caller, token);
        }
        return 0;
    }
    
    event RecordCollateralLow(address indexed caller, address indexed token, uint price);
    event RecordPoolHigh(address indexed caller, address indexed token, uint price);

}