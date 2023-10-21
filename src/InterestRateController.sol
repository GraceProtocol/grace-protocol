// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IPool {
    function getSupplied() external view returns (uint256);
    function totalDebt() external view returns (uint256);
}

interface ICore {
    function owner() external view returns (address);
}

contract InterestRateController {

    struct PoolState {
        uint utilCumulative;
        uint lastUtilBps;
        uint lastUtilUpdate;
        uint lastBorrowRateUpdate;
        uint borrowRate;
        uint minRate;
    }

    address public immutable core;
    uint public constant UPDATE_PERIOD = 1 days;
    uint public constant RATE_STEP_BPS = 100;
    uint public constant RATE_KINK_BPS = 8000;

    mapping (address => PoolState) public poolStates;

    constructor(address _core) {
        core = _core;
    }

    function getBorrowRateBps(address pool) external view returns (uint256) {
        return poolStates[pool].borrowRate;
    }

    function update(address pool) external {
        require(msg.sender == core, "onlyCore");
        IPool poolContract = IPool(pool);
        uint supplied = poolContract.getSupplied();
        uint currentUtilBps;
        uint debt = poolContract.totalDebt();
        if (supplied > 0) currentUtilBps = debt * 10000 / supplied; // else util is already 0
        uint utilBps = poolStates[pool].lastUtilBps;
        poolStates[pool].lastUtilBps = currentUtilBps;
        uint lastUtilUpdate = poolStates[pool].lastUtilUpdate;
        uint utilTimeElapsed = block.timestamp - lastUtilUpdate;
        if(utilTimeElapsed > 0 && lastUtilUpdate > 0) {
            poolStates[pool].utilCumulative += utilBps * utilTimeElapsed;
        }
        poolStates[pool].lastUtilUpdate = block.timestamp;
        uint lastBorrowRateUpdate = poolStates[pool].lastBorrowRateUpdate;
        uint rateTimeElapsed = block.timestamp - lastBorrowRateUpdate;
        if(rateTimeElapsed >= UPDATE_PERIOD) {
            uint utilCumulative = poolStates[pool].utilCumulative / lastBorrowRateUpdate;
            poolStates[pool].utilCumulative = 0;
            if(utilCumulative >= RATE_KINK_BPS) {
                poolStates[pool].borrowRate += RATE_STEP_BPS;
            } else if(poolStates[pool].borrowRate > RATE_STEP_BPS) {
                uint prevBorrowRate = poolStates[pool].borrowRate;
                uint minRate = poolStates[pool].minRate;
                poolStates[pool].borrowRate = prevBorrowRate - RATE_STEP_BPS > minRate ? prevBorrowRate - RATE_STEP_BPS : minRate;
            } else {
                poolStates[pool].borrowRate = poolStates[pool].minRate;
            }
            poolStates[pool].lastBorrowRateUpdate = block.timestamp;
        }
    }

    function setMinRate(address pool, uint rate) external {
        require(msg.sender == ICore(core).owner(), "onlyCoreOwner");
        poolStates[pool].minRate = rate;
        if(poolStates[pool].borrowRate < rate) poolStates[pool].borrowRate = rate;
    }   
}