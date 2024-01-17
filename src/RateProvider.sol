// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

interface IRateModel {
    function getRateBps(uint util, uint lastRate, uint lastAccrued) external view returns (uint256);
}

contract RateProvider {

    uint constant MAX_BORROW_RATE_BPS = 1000000; // 10,000%
    uint constant MAX_COLLATERAL_FEE_BPS = 1000000; // 10,000%
    address public owner;
    address public defaultInterestRateModel;
    address public defaultCollateralFeeModel;
    mapping(address => address) public interestRateModels; // pool contract => model
    mapping(address => address) public collateralFeeModels; // collateral contract => model

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    function setOwner(address _owner) external onlyOwner { owner = _owner; }
    function setDefaultInterestRateModel(address _defaultInterestRateModel) external onlyOwner { defaultInterestRateModel = _defaultInterestRateModel; }
    function setDefaultCollateralFeeModel(address _defaultCollateralFeeModel) external onlyOwner { defaultCollateralFeeModel = _defaultCollateralFeeModel; }
    function setInterestRateModel(address pool, address model) external onlyOwner { interestRateModels[pool] = model; }
    function setCollateralFeeModel(address collateral, address model) external onlyOwner { collateralFeeModels[collateral] = model; }

    function getCollateralFeeModelOf(address collateral) public view returns (address) {
        address model = collateralFeeModels[collateral];
        if(model == address(0)) {
            model = defaultCollateralFeeModel;
        }
        return model;
    }

    function getCollateralFeeModelFeeBps(address collateral, uint util, uint lastBorrowRate, uint lastAccrued) external view returns (uint256) {
        address model = getCollateralFeeModelOf(collateral);
        if(model == address(0)) {
            return 0;
        }
        uint rate = IRateModel(model).getRateBps(util, lastBorrowRate, lastAccrued);
        if(rate > MAX_COLLATERAL_FEE_BPS) {
            rate = MAX_COLLATERAL_FEE_BPS;
        }
        return rate;
    }

    function getInterestRateModelOf(address pool) public view returns (address) {
        address model = interestRateModels[pool];
        if(model == address(0)) {
            model = defaultInterestRateModel;
        }
        return model;
    }

    function getInterestRateModelBorrowRate(address pool, uint util, uint lastBorrowRate, uint lastAccrued) external view returns (uint256) {
        address model = getInterestRateModelOf(pool);
        if(model == address(0)) {
            return 0;
        }
        uint rate = IRateModel(model).getRateBps(util, lastBorrowRate, lastAccrued);
        if(rate > MAX_BORROW_RATE_BPS) {
            rate = MAX_BORROW_RATE_BPS;
        }
        return rate;
    }

    
}