// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./EMA.sol";

interface ICore {
    function owner() external view returns (address);
}

contract InterestRateController {

    using EMA for EMA.EMAState;

    uint constant KINK_BPS = 9000;
    uint constant HALF_LIFE = 1 days;

    struct PoolState {
        uint minRate;
        uint kinkRate;
        uint maxRate;
    }

    address public immutable core;

    mapping (address => PoolState) public poolStates;

    constructor(address _core) {
        core = _core;
    }

    function getCurveRate(address pool, uint util) public view returns (uint) {
        PoolState memory state = poolStates[pool];
        if(util < KINK_BPS) {
            return state.minRate + util * (state.kinkRate - state.minRate) / KINK_BPS;
        } else {
            return state.kinkRate + (util - KINK_BPS) * (state.maxRate - state.kinkRate) / (10000 - KINK_BPS);
        }
    }

    function getBorrowRateBps(address pool, uint util, uint lastBorrowRate, uint lastAccrued) external view returns (uint256) {
        uint curveRate = getCurveRate(pool, util);
        // apply EMA to smoothen rate change
        EMA.EMAState memory rateEMA;
        rateEMA.lastUpdate = lastAccrued;
        rateEMA.ema = lastBorrowRate;
        rateEMA = rateEMA.update(curveRate, HALF_LIFE);
        return rateEMA.ema;
    }

    function setPoolRates(address pool, uint minRate, uint kinkRate, uint maxRate) external {
        require(msg.sender == ICore(core).owner(), "onlyCoreOwner");
        poolStates[pool].minRate = minRate;
        poolStates[pool].kinkRate = kinkRate;
        poolStates[pool].maxRate = maxRate;
    }
}