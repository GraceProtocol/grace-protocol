// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./Oracle.sol";

interface IPoolDeployer {
    function deployPool(string memory name, string memory symbol, address underlying) external returns (address pool);
}

interface ICollateralDeployer {
    function deployCollateral(address underlying) external returns (address collateral);
}

interface IInterestRateController {
    function getBorrowRateBps(address pool) external view returns (uint256);
    function update(address pool) external;
}

interface ICollateralFeeController {
    function getCollateralFeeBps(address collateral) external view returns (uint256);
    function update(address collateral, uint collateralPriceMantissa, uint capUsd) external;
}

interface IPool {
    function token() external view returns (address);
    function getSupplied() external view returns (uint);
    function getDebtOf(address account) external view returns (uint);
    function repay(address to, uint amount) external;
    function writeOff(address account) external;
    function pull(address _stuckToken, address dst, uint amount) external;
}

interface ICollateral {
    function token() external view returns (address);
    function getTotalCollateral() external view returns (uint);
    function getCollateralOf(address account) external view returns (uint256);
    function seize(address account, uint256 amount, address to) external;
    function pull(address _stuckToken, address dst, uint amount) external;
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns(bool);
}

contract Core {

    struct CollateralConfig {
        bool enabled;
        uint collateralFactorBps;
        uint hardCap;
        uint softCapBps;
        bool depositPaused;
        bool depositSuspended;
    }

    struct PoolConfig {
        bool enabled;
        uint depositCap;
        bool borrowPaused;
        bool borrowSuspended;
    }

    IPoolDeployer public immutable poolDeployer;
    ICollateralDeployer public immutable collateralDeployer;
    uint public constant MAX_SOFT_CAP = 2000;
    uint public liquidationIncentiveBps = 1000; // 10%
    uint public maxLiquidationIncentiveUsd = 1000e18; // $1,000
    uint public badDebtCollateralThresholdUsd = 1000e18; // $1000
    uint lastSupplyValueWeeklyLowValue;
    uint lastSupplyValueWeeklyLowUpdate;
    uint256 public lockDepth;
    address public owner;
    Oracle public immutable oracle = new Oracle();
    IInterestRateController public interestRateController;
    ICollateralFeeController public collateralFeeController;
    address public feeDestination = address(this);
    uint constant MANTISSA = 1e18;
    uint constant MAX_BORROW_RATE_BPS = 1000000; // 10,000%
    uint constant MAX_COLLATERAL_FACTOR_BPS = 1000000; // 10,000%
    uint public dailyBorrowLimitUsd = 100000e18; // $100,000
    address public guardian;
    mapping (ICollateral => CollateralConfig) public collateralsData;
    mapping (IPool => PoolConfig) public poolsData;
    mapping (address => IPool) public underlyingToPool;
    mapping (address => ICollateral) public underlyingToCollateral;
    mapping (ICollateral => mapping (address => bool)) public collateralUsers;
    mapping (IPool => mapping (address => bool)) public poolUsers;
    mapping (address => ICollateral[]) public userCollaterals;
    mapping (address => IPool[]) public userPools;
    mapping (uint => uint) public supplyValueSemiWeeklyLowUsd;
    mapping (uint => uint) public dailyBorrowsUsd;
    IPool[] public poolList;
    ICollateral[] public collateralList;

    constructor(address _owner, address _poolDeployer, address _collateralDeployer) {
        owner = _owner;
        poolDeployer = IPoolDeployer(_poolDeployer);
        collateralDeployer = ICollateralDeployer(_collateralDeployer);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    function setOwner(address _owner) public onlyOwner { owner = _owner; }
    function setFeeDestination(address _feeDestination) public onlyOwner { feeDestination = _feeDestination; }
    function setInterestRateController(IInterestRateController _interestRateController) public onlyOwner { interestRateController = _interestRateController; }
    function setCollateralFeeController(ICollateralFeeController _collateralFeeController) public onlyOwner { collateralFeeController = _collateralFeeController; }
    function setLiquidationIncentiveBps(uint _liquidationIncentiveBps) public onlyOwner { liquidationIncentiveBps = _liquidationIncentiveBps; }
    function setMaxLiquidationIncentiveUsd(uint _maxLiquidationIncentiveUsd) public onlyOwner { maxLiquidationIncentiveUsd = _maxLiquidationIncentiveUsd; }
    function setBadDebtCollateralThresholdUsd(uint _badDebtCollateralThresholdUsd) public onlyOwner { badDebtCollateralThresholdUsd = _badDebtCollateralThresholdUsd; }
    function setDailyBorrowLimitUsd(uint _dailyBorrowLimitUsd) public onlyOwner { dailyBorrowLimitUsd = _dailyBorrowLimitUsd; }
    function setGuardian(address _guardian) public onlyOwner { guardian = _guardian; }
    function setPoolBorrowPaused(IPool pool, bool paused) public {
        require(msg.sender == guardian || msg.sender == owner, "onlyGuardianOrOwner");
        require(poolsData[pool].borrowSuspended == false, "borrowSuspended");
        poolsData[pool].borrowPaused = paused;
    }
    function setPoolBorrowSuspended(IPool pool, bool suspended) public onlyOwner { 
        poolsData[pool].borrowSuspended = suspended;
        if(suspended) poolsData[pool].borrowPaused = true;
    }
    function setCollateralDepositPaused(ICollateral collateral, bool paused) public {
        require(msg.sender == guardian || msg.sender == owner, "onlyGuardianOrOwner");
        require(collateralsData[collateral].depositSuspended == false, "depositSuspended");
        collateralsData[collateral].depositPaused = paused;
    }
    function setCollateralDepositSuspended(ICollateral collateral, bool suspended) public onlyOwner { 
        collateralsData[collateral].depositSuspended = suspended;
        if(suspended) collateralsData[collateral].depositPaused = true;
    }

    function globalLock(address caller) external {
        require(collateralsData[ICollateral(msg.sender)].enabled || poolsData[IPool(msg.sender)].enabled, "onlyCollateralsOrPools");
        // exempt core from lock enforcement
        require(lockDepth == 0 || caller == address(this), "locked");
        lockDepth += 1;
    }

    function globalUnlock() external {
        require(collateralsData[ICollateral(msg.sender)].enabled || poolsData[IPool(msg.sender)].enabled, "onlyCollateralsOrPools");
        lockDepth -= 1;
    }

    modifier lock() {
        // exempt trusted contracts from lock enforcement
        require(lockDepth == 0 || collateralsData[ICollateral(msg.sender)].enabled || poolsData[IPool(msg.sender)].enabled, "locked");
        lockDepth += 1;
        _;
        lockDepth -= 1;
    }

    function deployPool(string memory name, string memory symbol, address underlying, address feed, uint depositCap) public onlyOwner returns (address) {
        require(underlyingToPool[underlying] == IPool(address(0)), "underlyingAlreadyAdded");
        uint size;
        assembly { size := extcodesize(underlying) }
        require(size > 0, "invalidUnderlying");
        IPool pool = IPool(poolDeployer.deployPool(name, symbol, underlying));
        poolsData[pool] = PoolConfig({
            enabled: true,
            depositCap: depositCap,
            borrowPaused: false,
            borrowSuspended: false
        });
        oracle.setPoolFeed(underlying, feed);
        poolList.push(pool);
        underlyingToPool[underlying] = pool;
        return address(pool);
    }

    function setPoolFeed(IPool pool, address feed) public onlyOwner {
        require(poolsData[pool].enabled == true, "poolNotAdded");
        oracle.setPoolFeed(address(pool), feed);
    }

    function setPoolDepositCap(IPool pool, uint depositCap) public onlyOwner {
        require(poolsData[pool].enabled == true, "poolNotAdded");
        poolsData[pool].depositCap = depositCap;
    }

    function deployCollateral(
        address underlying,
        address feed,
        uint collateralFactor,
        uint hardCapUsd,
        uint softCapBps
        ) public onlyOwner returns (address) {
        require(underlyingToCollateral[underlying] == ICollateral(address(0)), "underlyingAlreadyAdded");
        require(collateralFactor < 10000, "collateralFactorTooHigh");
        require(softCapBps <= MAX_SOFT_CAP, "softCapTooHigh");
        uint size;
        assembly { size := extcodesize(underlying) }
        require(size > 0, "invalidUnderlying");
        ICollateral collateral = ICollateral(collateralDeployer.deployCollateral(underlying));
        collateralsData[collateral] = CollateralConfig({
            enabled: true,
            collateralFactorBps: collateralFactor,
            hardCap: hardCapUsd,
            softCapBps: softCapBps
        });
        oracle.setCollateralFeed(underlying, feed);
        collateralList.push(collateral);
        underlyingToCollateral[underlying] = collateral;
        return address(collateral);
    }

    function setCollateralFeed(ICollateral collateral, address feed) public onlyOwner {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        oracle.setCollateralFeed(address(collateral.token()), feed);
    }

    function setCollateralFactor(ICollateral collateral, uint collateralFactor) public onlyOwner {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        require(collateralFactor < 10000, "collateralFactorTooHigh");
        collateralsData[collateral].collateralFactorBps = collateralFactor;
    }

    function setCollateralHardCap(ICollateral collateral, uint hardCapUsd) public onlyOwner {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        collateralsData[collateral].hardCap = hardCapUsd;
    }

    function setCollateralSoftCap(ICollateral collateral, uint softCapBps) public onlyOwner {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        require(softCapBps <= MAX_SOFT_CAP, "softCapTooHigh");
        collateralsData[collateral].softCapBps = softCapBps;
    }

    function updateCollateralFeeController() external {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "onlyCollaterals");
        uint weekLow = getSupplyValueWeeklyLow();
        uint sofCapUsd = getSoftCapUsd(collateral, weekLow);
        uint capUsd = collateralsData[collateral].hardCap < sofCapUsd ? collateralsData[collateral].hardCap : sofCapUsd;
        uint price = oracle.getCollateralPriceMantissa(
            address(collateral),
            collateralsData[collateral].collateralFactorBps,
            collateral.getTotalCollateral(),
            capUsd
        );
        collateralFeeController.update(address(collateral), price, capUsd);
    }

    function getSupplyValueUsd() internal returns (uint256) {
        uint totalValueUsd = 0;
        for (uint i = 0; i < poolList.length; i++) {
            IPool pool = poolList[i];
            uint supplied = pool.getSupplied();
            uint price = oracle.getDebtPriceMantissa(address(pool));
            totalValueUsd += supplied * price / MANTISSA;
        }
        return totalValueUsd;
    }

    function getSupplyValueWeeklyLow() internal returns (uint) {
        if(lastSupplyValueWeeklyLowUpdate == block.timestamp) return lastSupplyValueWeeklyLowValue;
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
        uint supplyValueWeeklyLow =  lastSemiWeekLow < semiWeekLow && lastSemiWeekLow > 0 ? lastSemiWeekLow : semiWeekLow;
        lastSupplyValueWeeklyLowValue = supplyValueWeeklyLow;
        lastSupplyValueWeeklyLowUpdate = block.timestamp;
        return supplyValueWeeklyLow;
    }

    function getSoftCapUsd(ICollateral collateral, uint weekLow) internal view returns (uint) {
        return weekLow * collateralsData[collateral].softCapBps / 10000;
    }

    function onCollateralDeposit(address, address recipient, uint256 amount) external returns (bool) {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");
        require(collateralsData[collateral].depositPaused == false, "depositPaused");
        // find soft cap in usd terms
        uint softCapUsd = getSoftCapUsd(collateral, getSupplyValueWeeklyLow());
        uint capUsd = collateralsData[collateral].hardCap < softCapUsd ? collateralsData[collateral].hardCap : softCapUsd;
        // get oracle price
        uint price = oracle.getCollateralPriceMantissa(
            address(collateral),
            collateralsData[collateral].collateralFactorBps,
            collateral.getTotalCollateral(),
            capUsd
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
        return true;
    }

    function onCollateralWithdraw(address caller, uint256 amount) external returns (bool) {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");

        // calculate liabilities
        uint liabilitiesUsd = 0;
        for (uint i = 0; i < userPools[caller].length; i++) {
            IPool pool = userPools[caller][i];
            uint debt = pool.getDebtOf(caller);
            uint price = oracle.getDebtPriceMantissa(address(pool));
            uint debtUsd = debt * price / MANTISSA;
            liabilitiesUsd += debtUsd;
        }

        // calculate assets
        uint assetsUsd = 0;
        // if liabilities == 0, skip assets check to save gas
        if(liabilitiesUsd > 0) {
            uint weekLow = getSupplyValueWeeklyLow();
            for (uint i = 0; i < userCollaterals[caller].length; i++) {
                ICollateral thisCollateral = userCollaterals[caller][i];
                uint sofCapUsd = getSoftCapUsd(thisCollateral, weekLow);
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
        return true;
    }

    function getCollateralFeeBps(address collateral) external view returns (uint256, address) {
        if (collateralsData[ICollateral(collateral)].enabled == false) return (0, address(0));
        if(feeDestination == address(0)) return (0, address(0));

        uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
        try Core(this).getCollateralFeeControllerFeeBps{gas:passedGas}(collateral) returns (uint256 _feeBps) {
            if(_feeBps > MAX_COLLATERAL_FACTOR_BPS) _feeBps = MAX_COLLATERAL_FACTOR_BPS;
            return (_feeBps, feeDestination);
        } catch {
            return (0, address(0));
        }
    }

    function updateInterestRateController() external {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "onlyPools");
        interestRateController.update(address(pool));
    }

    function getInterestRateControllerBorrowRate(address pool) external view returns (uint256) {
        require(msg.sender == address(this), "onlyCore");
        return interestRateController.getBorrowRateBps(pool);
    }

    function getCollateralFeeControllerFeeBps(address collateral) external view returns (uint256) {
        require(msg.sender == address(this), "onlyCore");
        return collateralFeeController.getCollateralFeeBps(collateral);
    }

    function onPoolDeposit(address, address, uint256 amount) external view returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");
        require(pool.getSupplied() + amount <= poolsData[pool].depositCap, "depositCapExceeded");
        return true;
    }

    function onPoolBorrow(address caller, uint256 amount) external returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");
        require(poolsData[pool].borrowPaused == false, "borrowPaused");
        // if first borrow, add to userPools and poolUsers
        if(poolUsers[pool][caller] == false) {
            poolUsers[pool][caller] = true;
            userPools[caller].push(pool);
        }

        // calculate assets
        uint assetsUsd = 0;
        uint weekLow = getSupplyValueWeeklyLow();
        for (uint i = 0; i < userCollaterals[caller].length; i++) {
            ICollateral thisCollateral = userCollaterals[caller][i];
            uint sofCapUsd = getSoftCapUsd(thisCollateral, weekLow);
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
            IPool thisPool = userPools[caller][i];
            uint debt = thisPool.getDebtOf(caller);
            if(thisPool == pool) debt += amount;
            uint price = oracle.getDebtPriceMantissa(address(thisPool));
            uint debtUsd = debt * price / MANTISSA;
            if(thisPool == pool) {
                uint extraDebtUsd = amount * price / MANTISSA;
                uint day = block.timestamp / 1 days;
                require(extraDebtUsd + dailyBorrowsUsd[day] <= dailyBorrowLimitUsd, "dailyBorrowLimitExceeded");
                dailyBorrowsUsd[day] += extraDebtUsd;
            }
            liabilitiesUsd += debtUsd;
        }

        // check if assets are greater than liabilities
        require(assetsUsd >= liabilitiesUsd, "insufficientAssets");

        return true;
    }

    function onPoolRepay(address caller, address, uint256 amount) external returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");

        uint debt = pool.getDebtOf(caller);

        // if user repays all, remove from userPools and poolUsers
        if(amount == debt) {
            for (uint i = 0; i < userPools[caller].length; i++) {
                if(userPools[caller][i] == pool) {
                    userPools[caller][i] = userPools[caller][userPools[caller].length - 1];
                    userPools[caller].pop();
                    break;
                }
            }
            poolUsers[pool][caller] = false;
        }

        // reduce daily borrows
        uint price = oracle.getDebtPriceMantissa(address(pool));
        uint repaidDebtUsd = amount * price / MANTISSA;
        uint day = block.timestamp / 1 days;
        if(dailyBorrowsUsd[day] > repaidDebtUsd) {
            unchecked { dailyBorrowsUsd[day] -= repaidDebtUsd; }
        } else {
            dailyBorrowsUsd[day] = 0;
        }

        return true;
    }

    function getBorrowRateBps(address pool) external view returns (uint256, address) {
        if (interestRateController == IInterestRateController(address(0))) return (0, address(0));
        if(feeDestination == address(0)) return (0, address(0));
        
        uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
        try Core(this).getInterestRateControllerBorrowRate{gas: passedGas}(pool) returns (uint256 _borrowRateBps) {
            if(_borrowRateBps > MAX_BORROW_RATE_BPS) _borrowRateBps = MAX_BORROW_RATE_BPS;
            return (_borrowRateBps, feeDestination);
        } catch {
            return (0, address(0));
        }
    }

    function liquidate(address borrower, IPool pool, ICollateral collateral, uint debtAmount) lock external {
        require(collateralUsers[collateral][borrower], "notCollateralUser");
        require(poolUsers[pool][borrower], "notPoolUser");
        require(debtAmount > 0, "zeroDebtAmount");
        if(debtAmount == type(uint256).max) debtAmount = pool.getDebtOf(borrower);
        uint weekLow = getSupplyValueWeeklyLow();
        {
            uint liabilitiesUsd;
            {
                uint poolDebtUsd = pool.getDebtOf(borrower) * oracle.getDebtPriceMantissa(address(pool)) / MANTISSA;
                // calculate liabilities
                liabilitiesUsd = poolDebtUsd;
                for (uint i = 0; i < userPools[borrower].length; i++) {
                    IPool thisPool = userPools[borrower][i];
                    if (thisPool != pool) {
                        uint debt = thisPool.getDebtOf(borrower);
                        uint price = oracle.getDebtPriceMantissa(address(thisPool));
                        uint debtUsd = debt * price / MANTISSA;
                        require(debtUsd <= poolDebtUsd, "notMostDebtPool");
                        liabilitiesUsd += debtUsd;
                    }
                }
            }

            // calculate assets
            uint assetsUsd = 0;
            {
                // keep track of most valuable collateral
                uint collateralBalanceUsd = collateral.getCollateralOf(borrower) * oracle.getCollateralPriceMantissa(
                    address(collateral),
                    collateralsData[collateral].collateralFactorBps,
                    collateral.getTotalCollateral(),
                    collateralsData[collateral].hardCap < getSoftCapUsd(collateral, weekLow) ? collateralsData[collateral].hardCap : getSoftCapUsd(collateral, weekLow)
                ) / MANTISSA;

                for (uint i = 0; i < userCollaterals[borrower].length; i++) {
                    ICollateral thisCollateral = userCollaterals[borrower][i];
                    uint sofCapUsd = getSoftCapUsd(thisCollateral, weekLow);
                    uint capUsd = collateralsData[thisCollateral].hardCap < sofCapUsd ? collateralsData[thisCollateral].hardCap : sofCapUsd;
                    uint price = oracle.getCollateralPriceMantissa(
                        address(thisCollateral),
                        collateralsData[thisCollateral].collateralFactorBps,
                        thisCollateral.getTotalCollateral(),
                        capUsd
                    );
                    uint thisCollateralBalance = thisCollateral.getCollateralOf(borrower);
                    uint thisCollateralUsd = thisCollateralBalance * collateralsData[thisCollateral].collateralFactorBps * price / 10000 / MANTISSA;
                    if(thisCollateral != collateral) {
                        require(thisCollateralUsd <= collateralBalanceUsd, "notMostValuableCollateral");
                    }
                    assetsUsd += thisCollateralUsd;
                }
            }
            require(assetsUsd < liabilitiesUsd, "insufficientLiabilities");
        }

        {
            // calculate collateral reward
            uint debtPrice = oracle.getDebtPriceMantissa(address(pool));
            uint debtValue = debtAmount * debtPrice / MANTISSA;
            uint collateralPrice = oracle.getCollateralPriceMantissa(
                address(collateral),
                collateralsData[collateral].collateralFactorBps,
                collateral.getTotalCollateral(),
                collateralsData[collateral].hardCap < getSoftCapUsd(collateral, weekLow) ? collateralsData[collateral].hardCap : getSoftCapUsd(collateral, weekLow)
            );
            uint collateralAmount = debtValue * MANTISSA / collateralPrice;
            uint collateralIncentive = collateralAmount * liquidationIncentiveBps / 10000;
            uint collateralIncentiveUsd = collateralIncentive * collateralPrice / MANTISSA;
            uint collateralReward = collateralAmount + collateralIncentive;
            
            // enforce max liquidation incentive
            require(collateralIncentiveUsd <= maxLiquidationIncentiveUsd, "maxLiquidationIncentiveExceeded");

            IERC20 debtToken = IERC20(address(pool.token()));
            debtToken.transferFrom(msg.sender, address(this), debtAmount);
            debtToken.approve(address(pool), debtAmount);
            pool.repay(borrower, debtAmount);
            collateral.seize(borrower, collateralReward, msg.sender);
        }

        if(collateral.getCollateralOf(borrower) == 0) {
            // remove from userCollaterals and collateralUsers
            for (uint i = 0; i < userCollaterals[borrower].length; i++) {
                if(userCollaterals[borrower][i] == collateral) {
                    userCollaterals[borrower][i] = userCollaterals[borrower][userCollaterals[borrower].length - 1];
                    userCollaterals[borrower].pop();
                    break;
                }
            }
            collateralUsers[collateral][borrower] = false;
        }
    }

    function writeOff(address borrower) public lock {
        // calculate liabilities
        uint liabilitiesUsd = 0;
        for (uint i = 0; i < userPools[borrower].length; i++) {
            IPool thisPool = userPools[borrower][i];
            uint debt = thisPool.getDebtOf(borrower);
            uint price = oracle.getDebtPriceMantissa(address(thisPool));
            uint debtUsd = debt * price / MANTISSA;
            liabilitiesUsd += debtUsd;
        }

        require(liabilitiesUsd > 0, "noLiabilities");

        // calculate assets, without applying collateral factor
        uint assetsUsd = 0;
        uint weekLow = getSupplyValueWeeklyLow();
        for (uint i = 0; i < userCollaterals[borrower].length; i++) {
            ICollateral thisCollateral = userCollaterals[borrower][i];
            uint sofCapUsd = getSoftCapUsd(thisCollateral, weekLow);
            uint capUsd = collateralsData[thisCollateral].hardCap < sofCapUsd ? collateralsData[thisCollateral].hardCap : sofCapUsd;
            uint price = oracle.getCollateralPriceMantissa(
                address(thisCollateral),
                collateralsData[thisCollateral].collateralFactorBps,
                thisCollateral.getTotalCollateral(),
                capUsd
            );
            uint thisCollateralBalance = thisCollateral.getCollateralOf(borrower);
            uint thisCollateralUsd = thisCollateralBalance * price / MANTISSA;
            require(thisCollateralUsd < badDebtCollateralThresholdUsd, "collateralBalanceTooHigh");
            assetsUsd += thisCollateralUsd;
        }

        require(assetsUsd < liabilitiesUsd, "insufficientLiabilities");

        // write off
        for (uint i = 0; i < userPools[borrower].length; i++) {
            IPool thisPool = userPools[borrower][i];
            thisPool.writeOff(borrower);
            poolUsers[thisPool][borrower] = false;
        }
        delete userPools[borrower];

        // seize
        for (uint i = 0; i < userCollaterals[borrower].length; i++) {
            ICollateral thisCollateral = userCollaterals[borrower][i];
            uint thisCollateralBalance = thisCollateral.getCollateralOf(borrower);
            thisCollateral.seize(borrower, thisCollateralBalance, feeDestination);
            collateralUsers[thisCollateral][borrower] = false;
        }
        delete userCollaterals[borrower];
    }

    function pullFromCore(IERC20 token, address dst, uint amount) public onlyOwner {
        token.transfer(dst, amount);
    }

    function pullFromPool(IPool pool, address token, address dst, uint amount) public onlyOwner {
        pool.pull(token, dst, amount);
    }

    function pullFromCollateral(ICollateral collateral, address token, address dst, uint amount) public onlyOwner {
        collateral.pull(token, dst, amount);
    }

    /// @notice Reset the lock counter in case of emergency
    function resetLock() public {
        require(msg.sender == tx.origin, "onlyExternals");
        lockDepth = 0;
    }

}