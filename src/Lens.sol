// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

interface ICore {
    function oracle() external view returns (address);
    function userCollateralsCount(address user) external view returns (uint256);
    function userCollaterals(address user, uint256 index) external view returns (address);
    function borrowerPoolsCount(address borrower) external view returns (uint256);
    function borrowerPools(address borrower, uint256 index) external view returns (address);
    function viewCollateralPriceMantissa(address collateral) external view returns (uint256);
    function viewDebtPriceMantissa(address pool) external view returns (uint256);
    function getCollateralFactor(address collateral) external view returns (uint);
}

interface ICollateral {
    function asset() external view returns (address);
    function getCollateralOf(address account) external view returns (uint256);
}

interface IPool {
    function asset() external view returns (address);
    function getDebtOf(address account) external view returns (uint);
    function accruedReferrerRewards(address referrer) external view returns (uint);
    function rewardIndexMantissa() external view returns (uint);
    function referrerIndexMantissa(address referrer) external view returns (uint);
    function referrerShares(address referrer) external view returns (uint);
    function totalReferrerShares() external view returns (uint);
    function convertToShares(uint amount) external view returns (uint);
    function lastAccrued() external view returns (uint);
    function lastBorrowRate() external view returns (uint);
    function totalDebt() external view returns (uint);
    function debtSupply() external view returns (uint);
}

interface IOracle {
    function viewDebtPriceMantissa(address caller, address token) external view returns (uint256);
}

interface IERC20 {
    function symbol() external view returns (string memory);
}

contract Lens {
    function getAssetsLiabilities(address core, address borrower) external view returns (uint256 assets, uint256 liabilities) {        
        
        for(uint i = 0; i < ICore(core).userCollateralsCount(borrower); i++) {
            address collateral = ICore(core).userCollaterals(borrower, i);
            uint collateralPrice = ICore(core).viewCollateralPriceMantissa(collateral);
            uint collateralAmount = ICollateral(collateral).getCollateralOf(borrower);
            uint collateralFactor = ICore(core).getCollateralFactor(collateral);
            assets += collateralPrice * collateralAmount * collateralFactor / 10000 / 1e18;
        }

        for(uint i = 0; i < ICore(core).borrowerPoolsCount(borrower); i++) {
            address pool = ICore(core).borrowerPools(borrower, i);
            uint debtPrice = IOracle(ICore(core).oracle()).viewDebtPriceMantissa(core, IPool(pool).asset());
            uint debtAmount = IPool(pool).getDebtOf(borrower);
            liabilities += debtPrice * debtAmount / 1e18;
        }

    }

    function getCollateralDeposits(address core, address borrower) external view returns (uint deposits) {
        for(uint i = 0; i < ICore(core).userCollateralsCount(borrower); i++) {
            address collateral = ICore(core).userCollaterals(borrower, i);
            uint collateralPrice = ICore(core).viewCollateralPriceMantissa(collateral);
            uint collateralAmount = ICollateral(collateral).getCollateralOf(borrower);
            deposits += collateralPrice * collateralAmount / 1e18;
        }
    }

    function getCollateralSymbols(address core, address borrower) external view returns (string memory symbols) {
        for(uint i = 0; i < ICore(core).userCollateralsCount(borrower); i++) {
            address collateral = ICore(core).userCollaterals(borrower, i);
            address asset = ICollateral(collateral).asset();
            string memory symbol = IERC20(asset).symbol();
            symbols = string(abi.encodePacked(symbols, symbol, " "));
        }
    }

    function getDebtSymbols(address core, address borrower) external view returns (string memory symbols) {
        for(uint i = 0; i < ICore(core).borrowerPoolsCount(borrower); i++) {
            address pool = ICore(core).borrowerPools(borrower, i);
            address asset = IPool(pool).asset();
            string memory symbol = IERC20(asset).symbol();
            symbols = string(abi.encodePacked(symbols, symbol, " "));
        }
    }

    function getReferrerReward(address core, address pool, address referrer) external view returns (uint reward) {
        reward = IPool(pool).accruedReferrerRewards(referrer);
        uint timeElapsed = block.timestamp - IPool(pool).lastAccrued();
        uint interest = IPool(pool).totalDebt() * IPool(pool).lastBorrowRate() * timeElapsed / 10000 / 365 days;
        uint shares = IPool(pool).convertToShares(interest);
        uint referrerReward = shares * IPool(pool).totalReferrerShares() * 1000 / IPool(pool).debtSupply() / 10000;
        uint rewardIndexMantissa = IPool(pool).rewardIndexMantissa() + (referrerReward * 1e18 / IPool(pool).totalReferrerShares());
        uint deltaIndex = rewardIndexMantissa - IPool(pool).referrerIndexMantissa(referrer);
        uint bal = IPool(pool).referrerShares(referrer);
        uint referrerDelta = bal * deltaIndex;
        reward += referrerDelta / 1e18;
    }
}