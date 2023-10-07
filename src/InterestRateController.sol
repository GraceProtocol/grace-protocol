// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IPool {
    function getSupplied() external view returns (uint256);
    function totalDebt() external view returns (uint256);
}

contract InterestRateModel {

    struct PoolState {
        uint utilCumulative;
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
        uint utilBps;
        uint debt = poolContract.totalDebt();
        if (supplied > 0) utilBps = debt * 10000 / supplied; // else util is already 0
        uint utilTimeElapsed = block.timestamp - poolStates[pool].lastUtilUpdate;
        if(utilTimeElapsed > 0 && poolStates[pool].lastUtilUpdate > 0) {
            poolStates[pool].utilCumulative += utilBps * utilTimeElapsed;
        }
        poolStates[pool].lastUtilUpdate = block.timestamp;
        uint rateTimeElapsed = block.timestamp - poolStates[pool].lastBorrowRateUpdate;
        if(rateTimeElapsed >= UPDATE_PERIOD) {
            uint utilCumulative = poolStates[pool].utilCumulative / UPDATE_PERIOD;
            poolStates[pool].utilCumulative = 0;
            if(utilCumulative >= RATE_KINK_BPS) {
                poolStates[pool].borrowRate += RATE_STEP_BPS;
            } else if(poolStates[pool].borrowRate > RATE_STEP_BPS) {
                poolStates[pool].borrowRate = poolStates[pool].borrowRate - RATE_STEP_BPS > poolStates[pool].minRate ? poolStates[pool].borrowRate - RATE_STEP_BPS : poolStates[pool].minRate;
            } else {
                poolStates[pool].borrowRate = poolStates[pool].minRate;
            }
            poolStates[pool].lastBorrowRateUpdate = block.timestamp;
        }
    }
}