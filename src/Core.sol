// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IOracle {
    function getPessimisticPriceMantissa(address token, uint collateralFactorBps) external view returns (uint256);
    function getWeeklyHighMantissa(address token) external view returns (uint256);
}

interface ICollateral {
    function getTotalCollateral() external view returns (uint256);
    function getCollateralOf(address account) external view returns (uint256);
}

interface IPool {
    function getSupplied() external view returns (uint256);
    function getDebtOf(address account) external view returns (uint);
}

interface IInterestRateModel {
    function getBorrowRateBps(address pool) external view returns (uint256);
    function update(address pool) external;
}

interface ICollateralFeeModel {
    function getCollateralFeeBps(address collateral) external view returns (uint256);
    function update(address collateral) external;
}

contract Core {

    struct CollateralConfig {
        bool enabled;
        uint collateralFactorBps;
        uint hardCap;
        uint softCapBps;
    }

    struct PoolConfig {
        bool enabled;
        uint depositCap;
    }

    uint public constant MAX_SOFT_CAP = 1500;
    uint public constant MIN_ADD_COLLATERAL_DELAY = 30 days;
    uint public constant MIN_ADD_POOL_DELAY = 30 days;
    address public owner;
    IOracle public oracle;
    IInterestRateModel public interestRateModel;
    ICollateralFeeModel public collateralFeeModel;
    address public feeDestination;
    uint public lastAddCollateralTime;
    uint public lastAddPoolTime;
    uint constant MANTISSA = 1e18;
    mapping (ICollateral => CollateralConfig) public collateralsData;
    mapping (IPool => PoolConfig) public poolsData;
    mapping (ICollateral => mapping (address => bool)) public collateralUsers;
    mapping (IPool => mapping (address => bool)) public poolUsers;
    mapping (address => ICollateral[]) public userCollaterals;
    mapping (address => IPool[]) public userPools;
    mapping (uint => uint) public supplyValueSemiWeeklyLowUsd;
    IPool[] public poolList;
    ICollateral[] public collateralList;

    constructor(address _owner, IOracle _oracle) {
        owner = _owner;
        oracle = _oracle;
    }

    /***
        Admin methods
    ***/

    modifier onlyOwner() {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    function setOwner(address _owner) public onlyOwner { owner = _owner; }
    function setOracle(IOracle _oracle) public onlyOwner { oracle = _oracle; }
    function setFeeDestination(address _feeDestination) public onlyOwner { feeDestination = _feeDestination; }
    function setInterestRateModel(IInterestRateModel _interestRateModel) public onlyOwner { interestRateModel = _interestRateModel; }
    function setCollateralFeeModel(ICollateralFeeModel _collateralFeeModel) public onlyOwner { collateralFeeModel = _collateralFeeModel; }

    function addPool(IPool pool, uint depositCap) public {
        require(msg.sender == owner, "onlyOwner");
        require(block.timestamp - lastAddPoolTime >= MIN_ADD_POOL_DELAY, "minDelayNotPassed");
        require(poolsData[pool].enabled == false, "poolAlreadyAdded");
        poolsData[pool] = PoolConfig({
            enabled: true,
            depositCap: depositCap
        });
        poolList.push(pool);
        lastAddPoolTime = block.timestamp;
    }

    function configPool(IPool pool, uint depositCap) public {
        require(msg.sender == owner, "onlyOwner");
        require(poolsData[pool].enabled == true, "poolNotAdded");
        poolsData[pool].depositCap = depositCap;
    }

    // TODO: Forbid adding same collateral underlying token using two different collateral contract
    function addCollateral(
        ICollateral collateral,
        uint collateralFactor,
        uint hardCapUsd,
        uint softCapBps
        ) public {
        require(msg.sender == owner, "onlyOwner");
        require(block.timestamp - lastAddCollateralTime >= MIN_ADD_COLLATERAL_DELAY, "minDelayNotPassed");
        require(collateralsData[collateral].enabled == false, "collateralAlreadyAdded");
        require(collateralFactor < 10000, "collateralFactorTooHigh");
        require(softCapBps <= MAX_SOFT_CAP, "softCapTooHigh");
        collateralsData[collateral] = CollateralConfig({
            enabled: true,
            collateralFactorBps: collateralFactor,
            hardCap: hardCapUsd,
            softCapBps: softCapBps
        });
        collateralList.push(collateral);
        lastAddCollateralTime = block.timestamp;
    }

    function configCollateral(
        ICollateral collateral,
        uint collateralFactor,
        uint hardCapUsd,
        uint softCapBps
        ) public {
        require(msg.sender == owner, "onlyOwner");
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        require(collateralFactor < 10000, "collateralFactorTooHigh");
        require(softCapBps <= MAX_SOFT_CAP, "softCapTooHigh");
        collateralsData[collateral].collateralFactorBps = collateralFactor;
        collateralsData[collateral].hardCap = hardCapUsd;
        collateralsData[collateral].softCapBps = softCapBps;
    }

    /***
        Collateral Hooks
    ***/

    function updateCollateralFeeModel(address collateral) external {
        require(msg.sender == address(this), "onlyCore");
        collateralFeeModel.update(collateral);
    }

    function onCollateralDeposit(address, address recipient, uint256 amount) external returns (bool) {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");
        uint price = oracle.getPessimisticPriceMantissa(address(collateral), collateralsData[collateral].collateralFactorBps);
        uint totalCollateralAfter = collateral.getTotalCollateral() + amount;
        uint totalValueAfter = totalCollateralAfter * price / MANTISSA;
        require(totalValueAfter <= collateralsData[collateral].hardCap, "hardCapExceeded");
        uint currentSupplyValueUsd = getSupplyValueUsd();
        uint semiWeek = block.timestamp / 0.5 weeks;
        uint semiWeekLow = supplyValueSemiWeeklyLowUsd[semiWeek];
        if(semiWeekLow == 0 || currentSupplyValueUsd < semiWeekLow) {
            supplyValueSemiWeeklyLowUsd[semiWeek] = currentSupplyValueUsd;
            semiWeekLow = currentSupplyValueUsd;
        }
        uint lastSemiWeekLow = supplyValueSemiWeeklyLowUsd[semiWeek - 1];
        uint weekLow = lastSemiWeekLow < semiWeekLow && lastSemiWeekLow > 0 ? lastSemiWeekLow : semiWeekLow;
        uint softCapUsd = weekLow * collateralsData[collateral].softCapBps / 10000;
        require(totalValueAfter <= softCapUsd, "softCapExceeded");
        if(collateralUsers[collateral][recipient] == false) {
            collateralUsers[collateral][recipient] = true;
            userCollaterals[recipient].push(collateral);
        }
        
        // update collateral fee model
        if(collateralFeeModel != ICollateralFeeModel(address(0))) {
            uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
            try Core(this).updateCollateralFeeModel{gas: passedGas}(address(collateral)) {} catch {}
        }
        return true;
    }

    // TODO: skip assets check if liabilities == 0
    function onCollateralWithdraw(address caller, uint256 amount) external returns (bool) {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");
        // calculate assets
        uint assetsUsd = 0;
        for (uint i = 0; i < userCollaterals[caller].length; i++) {
            ICollateral thisCollateral = userCollaterals[caller][i];
            uint price = oracle.getPessimisticPriceMantissa(address(thisCollateral), collateralsData[thisCollateral].collateralFactorBps);
            uint thisCollateralBalance = collateral.getCollateralOf(caller);
            if(thisCollateral == collateral) thisCollateralBalance -= amount;
            uint thisCollateralUsd = thisCollateralBalance * collateralsData[thisCollateral].collateralFactorBps * price / 10000 / MANTISSA;
            assetsUsd += thisCollateralUsd;
        }

        // calculate liabilities
        uint liabilitiesUsd = 0;
        for (uint i = 0; i < userPools[caller].length; i++) {
            IPool pool = userPools[caller][i];
            uint debt = pool.getDebtOf(caller);
            uint price = oracle.getWeeklyHighMantissa(address(pool));
            uint debtUsd = debt * price / MANTISSA;
            liabilitiesUsd += debtUsd;
        }

        // check if assets are greater than liabilities
        require(assetsUsd >= liabilitiesUsd, "insufficientAssets");

        // if user withdraws full collateral, remove from userCollaterals and collateralUsers
        if(amount == collateral.getCollateralOf(caller)) {
            for (uint i = 0; i < userCollaterals[caller].length; i++) {
                if(userCollaterals[caller][i] == collateral) {
                    userCollaterals[caller][i] = userCollaterals[caller][userCollaterals[caller].length - 1];
                    userCollaterals[caller].pop();
                    break;
                }
            }
            collateralUsers[collateral][caller] = false;
        }
        
        // update collateral fee model
        if(collateralFeeModel != ICollateralFeeModel(address(0))) {
            uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
            try Core(this).updateCollateralFeeModel{gas: passedGas}(address(collateral)) {} catch {}
        }
        return true;
    }

    function getCollateralFeeBps(address collateral) external view returns (uint256, address) {
        if (collateralsData[ICollateral(collateral)].enabled == false) return (0, address(0));
        if(feeDestination == address(0)) return (0, address(0));

        uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
        try Core(this).getCollateralFeeModelFeeBps{gas:passedGas}(collateral) returns (uint256 _feeBps) {
            return (_feeBps, feeDestination);
        } catch {
            return (0, address(0));
        }
    }

    /***
        Pool Hooks
    ***/

    function updateInterestRateModel(address pool) external {
        require(msg.sender == address(this), "onlyCore");
        interestRateModel.update(pool);
    }

    function getInterestRateModelBorrowRate(address pool) external view returns (uint256) {
        return interestRateModel.getBorrowRateBps(pool);
    }

    function getCollateralFeeModelFeeBps(address collateral) external view returns (uint256) {
        return collateralFeeModel.getCollateralFeeBps(collateral);
    }

    function onPoolDeposit(address, address, uint256 amount) external returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");
        require(pool.getSupplied() + amount <= poolsData[pool].depositCap, "depositCapExceeded");

        // update interest rate model
        if(interestRateModel != IInterestRateModel(address(0))) {
            uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
            try Core(this).updateInterestRateModel{gas: passedGas}(address(pool)) {} catch {}
        }

        return true;
    }

    function onPoolWithdraw(address, uint256) external returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");

        // update interest rate model
        if(interestRateModel != IInterestRateModel(address(0))) {
            uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
            try Core(this).updateInterestRateModel{gas: passedGas}(address(pool)) {} catch {}
        }   

        return true;
    }

    function onPoolBorrow(address caller, uint256 amount) external returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");

        // calculate assets
        uint assetsUsd = 0;
        for (uint i = 0; i < userCollaterals[caller].length; i++) {
            ICollateral thisCollateral = userCollaterals[caller][i];
            uint price = oracle.getPessimisticPriceMantissa(address(thisCollateral), collateralsData[thisCollateral].collateralFactorBps);
            uint thisCollateralBalance = thisCollateral.getCollateralOf(caller);
            uint thisCollateralUsd = thisCollateralBalance * collateralsData[thisCollateral].collateralFactorBps * price / 10000 / MANTISSA;
            assetsUsd += thisCollateralUsd;
        }

        // calculate liabilities
        uint liabilitiesUsd = 0;
        for (uint i = 0; i < userPools[caller].length; i++) {
            IPool thisPool = userPools[caller][i];
            uint debt = thisPool.getDebtOf(caller);
            if(thisPool == pool) debt += amount;
            uint price = oracle.getWeeklyHighMantissa(address(thisPool));
            uint debtUsd = debt * price / MANTISSA;
            liabilitiesUsd += debtUsd;
        }

        // check if assets are greater than liabilities
        require(assetsUsd >= liabilitiesUsd, "insufficientAssets");

        // if first borrow, add to userPools and poolUsers
        if(poolUsers[pool][caller] == false) {
            poolUsers[pool][caller] = true;
            userPools[caller].push(pool);
        }

        // update interest rate model
        if(interestRateModel != IInterestRateModel(address(0))) {
            uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
            try Core(this).updateInterestRateModel{gas: passedGas}(address(pool)) {} catch {}
        }

        return true;
    }

    function onPoolRepay(address caller, address, uint256 amount) external returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");

        // if user repays all, remove from userPools and poolUsers
        if(amount == pool.getDebtOf(caller)) {
            for (uint i = 0; i < userPools[caller].length; i++) {
                if(userPools[caller][i] == pool) {
                    userPools[caller][i] = userPools[caller][userPools[caller].length - 1];
                    userPools[caller].pop();
                    break;
                }
            }
            poolUsers[pool][caller] = false;
        }

        // update interest rate model
        if(interestRateModel != IInterestRateModel(address(0))) {
            uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
            try Core(this).updateInterestRateModel{gas: passedGas}(address(pool)) {} catch {}
        }

        return true;
    }

    function getBorrowRateBps(address pool) external view returns (uint256, address) {
        if (interestRateModel == IInterestRateModel(address(0))) return (0, address(0));
        if(feeDestination == address(0)) return (0, address(0));
        
        uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
        try Core(this).getInterestRateModelBorrowRate{gas: passedGas}(pool) returns (uint256 _borrowRateBps) {
            return (_borrowRateBps, feeDestination);
        } catch {
            return (0, address(0));
        }
    }

    /***
        Getters
    ***/

    function getSupplyValueUsd() public view returns (uint256) {
        uint totalValueUsd = 0;
        for (uint i = 0; i < poolList.length; i++) {
            IPool pool = poolList[i];
            uint supplied = pool.getSupplied();
            uint price = oracle.getWeeklyHighMantissa(address(pool));
            totalValueUsd += supplied * price / MANTISSA;
        }
        return totalValueUsd;
    }

}