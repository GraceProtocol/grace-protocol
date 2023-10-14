// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface ICollateral {
    function getTotalCollateral() external view returns (uint256);
}

interface ICore {
    function owner() external view returns (address);
}

contract CollateralFeeController {

    struct CollateralState {
        uint utilCumulative;
        uint lastUtilBps;
        uint lastUtilUpdate;
        uint lastFeeUpdate;
        uint fee;
        uint minFee;
    }

    address public immutable core;
    uint constant MANTISSA = 1e18;
    uint public constant UPDATE_PERIOD = 1 days;
    uint public constant FEE_STEP_BPS = 100;
    uint public constant FEE_KINK_BPS = 8000;

    mapping (address => CollateralState) public collateralStates;

    constructor(address _core) {
        core = _core;
    }

    function getCollateralFeeBps(address collateral) external view returns (uint256) {
        return collateralStates[collateral].fee;
    }

    function update(address collateral, uint collateralPriceMantissa, uint capUsd) external {
        require(msg.sender == core, "onlyCore");
        {
            ICollateral collateralContract = ICollateral(collateral);
            uint deposited = collateralContract.getTotalCollateral();
            uint depositedUsd = deposited * collateralPriceMantissa / MANTISSA;
            uint currentUtilBps = 10000;
            if (capUsd > 0) currentUtilBps = depositedUsd * 10000 / capUsd;
            uint utilBps = collateralStates[collateral].lastUtilBps;
            collateralStates[collateral].lastUtilBps = currentUtilBps;
            uint lastUtilUpdate = collateralStates[collateral].lastUtilUpdate;
            uint utilTimeElapsed = block.timestamp - lastUtilUpdate;
            if(utilTimeElapsed > 0 && lastUtilUpdate > 0) {
                collateralStates[collateral].utilCumulative += utilBps * utilTimeElapsed;
            }
            collateralStates[collateral].lastUtilUpdate = block.timestamp;
        }
        uint lastFeeUpdate = collateralStates[collateral].lastFeeUpdate;
        uint feeTimeElapsed = block.timestamp - lastFeeUpdate;
        if(feeTimeElapsed >= UPDATE_PERIOD) {
            uint utilCumulative = collateralStates[collateral].utilCumulative / lastFeeUpdate;
            collateralStates[collateral].utilCumulative = 0;
            if(utilCumulative >= FEE_KINK_BPS) {
                collateralStates[collateral].fee += FEE_STEP_BPS;
            } else if(collateralStates[collateral].fee > FEE_STEP_BPS) {
                uint prevFee = collateralStates[collateral].fee;
                uint minFee = collateralStates[collateral].minFee;
                collateralStates[collateral].fee = prevFee - FEE_STEP_BPS > minFee ? prevFee - FEE_STEP_BPS : minFee;
            } else {
                collateralStates[collateral].fee = collateralStates[collateral].minFee;
            }
            collateralStates[collateral].lastFeeUpdate = block.timestamp;
        }
    }

    function setMinFee(address collateral, uint fee) external {
        require(msg.sender == ICore(core).owner(), "onlyCoreOwner");
        collateralStates[collateral].minFee = fee;
        if(collateralStates[collateral].fee < fee) collateralStates[collateral].fee = fee;
    }   
}