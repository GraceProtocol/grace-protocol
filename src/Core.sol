// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./Oracle.sol";
import "./Collateral.sol";
import "./Pool.sol";

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

    uint public constant MAX_SOFT_CAP = 2000;
    uint public addCollateralDelay = 3 hours;
    uint public addPoolDelay = 3 hours;
    address public owner;
    Oracle public immutable oracle = new Oracle();
    IInterestRateModel public interestRateModel;
    ICollateralFeeModel public collateralFeeModel;
    address public feeDestination;
    uint public lastAddCollateralTime;
    uint public lastAddPoolTime;
    uint constant MANTISSA = 1e18;
    mapping (Collateral => CollateralConfig) public collateralsData;
    mapping (Pool => PoolConfig) public poolsData;
    mapping (address => Pool) public underlyingToPool;
    mapping (address => Collateral) public underlyingToCollateral;
    mapping (Collateral => mapping (address => bool)) public collateralUsers;
    mapping (Pool => mapping (address => bool)) public poolUsers;
    mapping (address => Collateral[]) public userCollaterals;
    mapping (address => Pool[]) public userPools;
    mapping (uint => uint) public supplyValueSemiWeeklyLowUsd;
    Pool[] public poolList;
    Collateral[] public collateralList;

    constructor(address _owner) {
        owner = _owner;
    }

    /***
        Admin methods
    ***/

    modifier onlyOwner() {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    function setOwner(address _owner) public onlyOwner { owner = _owner; }
    function setFeeDestination(address _feeDestination) public onlyOwner { feeDestination = _feeDestination; }
    function setInterestRateModel(IInterestRateModel _interestRateModel) public onlyOwner { interestRateModel = _interestRateModel; }
    function setCollateralFeeModel(ICollateralFeeModel _collateralFeeModel) public onlyOwner { collateralFeeModel = _collateralFeeModel; }

    function deployPool(address underlying, address feed, uint depositCap) public {
        require(msg.sender == owner, "onlyOwner");
        require(block.timestamp - lastAddPoolTime >= addPoolDelay, "minDelayNotPassed");
        require(underlyingToPool[underlying] == Pool(address(0)), "underlyingAlreadyAdded");
        uint size;
        assembly { size := extcodesize(underlying) }
        require(size > 0, "invalidUnderlying");
        Pool pool = new Pool(IPoolUnderlying(underlying));
        poolsData[pool] = PoolConfig({
            enabled: true,
            depositCap: depositCap
        });
        oracle.setPoolFeed(underlying, feed);
        poolList.push(pool);
        underlyingToPool[underlying] = pool;
        addPoolDelay *= 2;
        lastAddPoolTime = block.timestamp;
    }

    function configPool(Pool pool, address feed, uint depositCap) public {
        require(msg.sender == owner, "onlyOwner");
        require(poolsData[pool].enabled == true, "poolNotAdded");
        poolsData[pool].depositCap = depositCap;
        oracle.setPoolFeed(address(pool.token()), feed);
    }

    function deployCollateral(
        address underlying,
        address feed,
        uint collateralFactor,
        uint hardCapUsd,
        uint softCapBps
        ) public {
        require(msg.sender == owner, "onlyOwner");
        require(block.timestamp - lastAddCollateralTime >= addCollateralDelay, "minDelayNotPassed");
        require(underlyingToCollateral[underlying] == Collateral(address(0)), "underlyingAlreadyAdded");
        require(collateralFactor < 10000, "collateralFactorTooHigh");
        require(softCapBps <= MAX_SOFT_CAP, "softCapTooHigh");
        uint size;
        assembly { size := extcodesize(underlying) }
        require(size > 0, "invalidUnderlying");
        Collateral collateral = new Collateral(ICollateralUnderlying(underlying));
        collateralsData[collateral] = CollateralConfig({
            enabled: true,
            collateralFactorBps: collateralFactor,
            hardCap: hardCapUsd,
            softCapBps: softCapBps
        });
        oracle.setCollateralFeed(underlying, feed);
        collateralList.push(collateral);
        underlyingToCollateral[underlying] = collateral;
        addCollateralDelay *= 2;
        lastAddCollateralTime = block.timestamp;
    }

    function configCollateral(
        Collateral collateral,
        address feed,
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
        oracle.setCollateralFeed(address(collateral.token()), feed);
    }

    /***
        Collateral Hooks
    ***/

    function updateCollateralFeeModel(address collateral) external {
        require(msg.sender == address(this), "onlyCore");
        collateralFeeModel.update(collateral);
    }

    function getSupplyValueUsd() internal returns (uint256) {
        uint totalValueUsd = 0;
        for (uint i = 0; i < poolList.length; i++) {
            Pool pool = poolList[i];
            uint supplied = pool.getSupplied();
            uint price = oracle.getDebtPriceMantissa(address(pool));
            totalValueUsd += supplied * price / MANTISSA;
        }
        return totalValueUsd;
    }

    function getSupplyValueWeeklyLow() internal returns (uint) {
        // get all pools usd value
        uint currentSupplyValueUsd = getSupplyValueUsd();
        // find weekly low of all pool usd value
        uint semiWeek = block.timestamp / 0.5 weeks;
        uint semiWeekLow = supplyValueSemiWeeklyLowUsd[semiWeek];
        if(semiWeekLow == 0 || currentSupplyValueUsd < semiWeekLow) {
            supplyValueSemiWeeklyLowUsd[semiWeek] = currentSupplyValueUsd;
            semiWeekLow = currentSupplyValueUsd;
        }
        uint lastSemiWeekLow = supplyValueSemiWeeklyLowUsd[semiWeek - 1];
        return lastSemiWeekLow < semiWeekLow && lastSemiWeekLow > 0 ? lastSemiWeekLow : semiWeekLow;
    }

    function getSoftCapUsd(Collateral collateral) internal returns (uint) {
        uint weekLow = getSupplyValueWeeklyLow();
        return weekLow * collateralsData[collateral].softCapBps / 10000;
    }

    function onCollateralDeposit(address, address recipient, uint256 amount) external returns (bool) {
        Collateral collateral = Collateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");
        // find soft cap in usd terms
        uint softCapUsd = getSoftCapUsd(collateral);
        // get oracle price
        uint price = oracle.getCollateralPriceMantissa(
            address(collateral),
            collateralsData[collateral].collateralFactorBps,
            collateral.getTotalCollateral(),
            collateralsData[collateral].hardCap < softCapUsd ? collateralsData[collateral].hardCap : softCapUsd
            );
        // enforce both caps
        uint totalCollateralAfter = collateral.getTotalCollateral() + amount;
        uint totalValueAfter = totalCollateralAfter * price / MANTISSA;
        require(totalValueAfter <= collateralsData[collateral].hardCap, "hardCapExceeded");
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
        Collateral collateral = Collateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");
        // calculate assets
        uint assetsUsd = 0;
        for (uint i = 0; i < userCollaterals[caller].length; i++) {
            Collateral thisCollateral = userCollaterals[caller][i];
            uint sofCapUsd = getSoftCapUsd(thisCollateral);
            uint capUsd = collateralsData[thisCollateral].hardCap < sofCapUsd ? collateralsData[thisCollateral].hardCap : sofCapUsd;
            uint price = oracle.getCollateralPriceMantissa(
                address(thisCollateral),
                collateralsData[thisCollateral].collateralFactorBps,
                thisCollateral.getTotalCollateral(),
                capUsd
            );
            uint thisCollateralBalance = collateral.getCollateralOf(caller);
            if(thisCollateral == collateral) thisCollateralBalance -= amount;
            uint thisCollateralUsd = thisCollateralBalance * collateralsData[thisCollateral].collateralFactorBps * price / 10000 / MANTISSA;
            assetsUsd += thisCollateralUsd;
        }

        // calculate liabilities
        uint liabilitiesUsd = 0;
        for (uint i = 0; i < userPools[caller].length; i++) {
            Pool pool = userPools[caller][i];
            uint debt = pool.getDebtOf(caller);
            uint price = oracle.getDebtPriceMantissa(address(pool));
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
        if (collateralsData[Collateral(collateral)].enabled == false) return (0, address(0));
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
        Pool pool = Pool(msg.sender);
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
        Pool pool = Pool(msg.sender);
        require(poolsData[pool].enabled, "notPool");

        // update interest rate model
        if(interestRateModel != IInterestRateModel(address(0))) {
            uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
            try Core(this).updateInterestRateModel{gas: passedGas}(address(pool)) {} catch {}
        }   

        return true;
    }

    function onPoolBorrow(address caller, uint256 amount) external returns (bool) {
        Pool pool = Pool(msg.sender);
        require(poolsData[pool].enabled, "notPool");

        // calculate assets
        uint assetsUsd = 0;
        for (uint i = 0; i < userCollaterals[caller].length; i++) {
            Collateral thisCollateral = userCollaterals[caller][i];
            uint sofCapUsd = getSoftCapUsd(thisCollateral);
            uint capUsd = collateralsData[thisCollateral].hardCap < sofCapUsd ? collateralsData[thisCollateral].hardCap : sofCapUsd;
            uint price = oracle.getCollateralPriceMantissa(
                address(thisCollateral),
                collateralsData[thisCollateral].collateralFactorBps,
                thisCollateral.getTotalCollateral(),
                capUsd
            );
            uint thisCollateralBalance = thisCollateral.getCollateralOf(caller);
            uint thisCollateralUsd = thisCollateralBalance * collateralsData[thisCollateral].collateralFactorBps * price / 10000 / MANTISSA;
            assetsUsd += thisCollateralUsd;
        }

        // calculate liabilities
        uint liabilitiesUsd = 0;
        for (uint i = 0; i < userPools[caller].length; i++) {
            Pool thisPool = userPools[caller][i];
            uint debt = thisPool.getDebtOf(caller);
            if(thisPool == pool) debt += amount;
            uint price = oracle.getDebtPriceMantissa(address(thisPool));
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
        Pool pool = Pool(msg.sender);
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

}