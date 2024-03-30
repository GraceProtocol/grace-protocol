// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

contract RateModel {

    uint immutable public KINK_BPS;
    uint immutable public BPS_PER_DAY;
    uint immutable public MIN_RATE;
    uint immutable public KINK_RATE;
    uint immutable public MAX_RATE;

    constructor(uint _kinkBps, uint _bpsPerDay, uint _minRate, uint _kinkRate, uint _maxRate) {
        require(_kinkBps <= 10000, "kinkBps must be <= 10000");
        require(_minRate <= _kinkRate && _kinkRate <= _maxRate, "minRate <= kinkRate <= maxRate");
        require(_bpsPerDay > 0, "bpsPerDay must be > 0");
        KINK_BPS = _kinkBps;
        BPS_PER_DAY = _bpsPerDay;
        MIN_RATE = _minRate;
        KINK_RATE = _kinkRate;
        MAX_RATE = _maxRate;
    }

    function getTargetRate(uint util) public view returns (uint) {
        if(util < KINK_BPS) {
            // if util is below kink, rate grows linearly between MIN_RATE and KINK_RATE
            return MIN_RATE + util * (KINK_RATE - MIN_RATE) / KINK_BPS;
        } else {
            // if util is above kink, rate grows linearly between KINK_RATE and MAX_RATE
            return KINK_RATE + (util - KINK_BPS) * (MAX_RATE - KINK_RATE) / (10000 - KINK_BPS);
        }
    }

    function getRateBps(uint util, uint lastRate, uint lastAccrued) external view returns (uint256) {
        uint curveRate = getTargetRate(util);
        uint timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return lastRate;
        // we cap the rate of change per day at BPS_PER_DAY to reduce rate volatility
        uint maxChange = BPS_PER_DAY * timeElapsed / 1 days;
        if(curveRate > lastRate) { // rising
            return maxChange < curveRate - lastRate ? lastRate + maxChange : curveRate;
        } else { // falling
            return maxChange < lastRate - curveRate ? lastRate - maxChange : curveRate;
        }
        
    }
}