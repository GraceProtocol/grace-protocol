// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;


// This one is MIT licensed because it's a reusable model that can be useful for others

import "./EMA.sol";

contract RateModel {

    using EMA for EMA.EMAState;

    uint immutable public KINK_BPS;
    uint immutable public HALF_LIFE;
    uint immutable public MIN_RATE;
    uint immutable public KINK_RATE;
    uint immutable public MAX_RATE;

    constructor(uint _kinkBps, uint _halfLife, uint _minRate, uint _kinkRate, uint _maxRate) {
        require(_kinkBps <= 10000, "kinkBps must be <= 10000");
        require(_minRate <= _kinkRate && _kinkRate <= _maxRate, "minRate <= kinkRate <= maxRate");
        require(_halfLife > 0, "halfLife must be > 0");
        KINK_BPS = _kinkBps;
        HALF_LIFE = _halfLife;
        MIN_RATE = _minRate;
        KINK_RATE = _kinkRate;
        MAX_RATE = _maxRate;
    }

    function getTargetRate(uint util) public view returns (uint) {
        if(util < KINK_BPS) {
            return MIN_RATE + util * (KINK_RATE - MIN_RATE) / KINK_BPS;
        } else {
            return KINK_RATE + (util - KINK_BPS) * (MAX_RATE - KINK_RATE) / (10000 - KINK_BPS);
        }
    }

    function getRateBps(uint util, uint lastRate, uint lastAccrued) external view returns (uint256) {
        uint curveRate = getTargetRate(util);
        // apply EMA to create rate lag
        EMA.EMAState memory rateEMA;
        rateEMA.lastUpdate = lastAccrued;
        rateEMA.ema = lastRate;
        return rateEMA.simulateEMA(curveRate, HALF_LIFE);
    }
}