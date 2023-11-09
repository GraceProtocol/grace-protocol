// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;


// This one is MIT licensed because it's a reusable model that can be useful for others

import "./EMA.sol";

interface ICore {
    function owner() external view returns (address);
}

contract RateModel {

    using EMA for EMA.EMAState;

    uint constant KINK_BPS = 9000;
    uint constant HALF_LIFE = 3 days;

    struct RateConfig {
        uint minRate;
        uint kinkRate;
        uint maxRate;
    }

    address public immutable core;

    mapping (address => RateConfig) public configs;

    constructor(address _core) {
        core = _core;
    }

    function getCurveRate(address target, uint util) public view returns (uint) {
        RateConfig memory state = configs[target];
        if(util < KINK_BPS) {
            return state.minRate + util * (state.kinkRate - state.minRate) / KINK_BPS;
        } else {
            return state.kinkRate + (util - KINK_BPS) * (state.maxRate - state.kinkRate) / (10000 - KINK_BPS);
        }
    }

    function getRateBps(address target, uint util, uint lastRate, uint lastAccrued) external view returns (uint256) {
        uint curveRate = getCurveRate(target, util);
        // apply EMA to create rate lag
        EMA.EMAState memory rateEMA;
        rateEMA.lastUpdate = lastAccrued;
        rateEMA.ema = lastRate;
        return rateEMA.simulateEMA(curveRate, HALF_LIFE);
    }

    function setTargetRates(address target, uint minRate, uint kinkRate, uint maxRate) external {
        require(msg.sender == ICore(core).owner(), "onlyCoreOwner");
        require(minRate <= kinkRate && kinkRate <= maxRate, "invalidRates");
        configs[target].minRate = minRate;
        configs[target].kinkRate = kinkRate;
        configs[target].maxRate = maxRate;
    }
}