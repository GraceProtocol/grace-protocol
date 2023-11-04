// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./EMA.sol";
import "./Oracle.sol";

interface IPoolDeployer {
    function deployPool(string memory name, string memory symbol, address underlying) external returns (address pool);
}

interface ICollateralDeployer {
    function deployCollateral(string memory name, string memory symbol, address underlying) external returns (address collateral);
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
    function asset() external view returns (address);
    function totalAssets() external view returns (uint);
    function getDebtOf(address account) external view returns (uint);
    function repay(address to, uint amount) external;
    function writeOff(address account) external;
    function pull(address _stuckToken, address dst, uint amount) external;
}

interface ICollateral {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint);
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

    using EMA for EMA.EMAState;

    struct CollateralConfig {
        bool enabled;
        uint collateralFactorBps;
        uint hardCap;
        uint softCapBps;
        bool depositPaused;
        bool depositSuspended;
        // cap variables
        uint lastSoftCapUpdate;
        uint prevSoftCap;
        uint lastHardCapUpdate;
        uint prevHardCap;
        // collateral factor variables
        uint lastCollateralFactorUpdate;
        uint prevCollateralFactor;
    }

    struct PoolConfig {
        bool enabled;
        uint depositCap;
        bool borrowPaused;
        bool borrowSuspended;
        EMA.EMAState supplyEMA;
    }

    IPoolDeployer public immutable poolDeployer;
    ICollateralDeployer public immutable collateralDeployer;
    uint public constant MAX_SOFT_CAP = 2000;
    uint public liquidationIncentiveBps = 1000; // 10%
    uint public maxLiquidationIncentiveUsd = 1000e18; // $1,000
    uint public badDebtCollateralThresholdUsd = 1000e18; // $1000
    uint public supplyEMASum;
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
        EMA.EMAState memory emaState;
        emaState = emaState.init();
        poolsData[pool] = PoolConfig({
            enabled: true,
            depositCap: depositCap,
            borrowPaused: false,
            borrowSuspended: false,
            supplyEMA: emaState
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
        string memory name,
        string memory symbol,
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
        ICollateral collateral = ICollateral(collateralDeployer.deployCollateral(name, symbol, underlying));
        collateralsData[collateral] = CollateralConfig({
            enabled: true,
            collateralFactorBps: collateralFactor,
            hardCap: hardCapUsd,
            softCapBps: softCapBps,
            depositPaused: false,
            depositSuspended: false,
            lastSoftCapUpdate: block.timestamp,
            prevSoftCap: 0,
            lastHardCapUpdate: block.timestamp,
            prevHardCap: 0,
            lastCollateralFactorUpdate: block.timestamp,
            prevCollateralFactor: 0
        });
        oracle.setCollateralFeed(underlying, feed);
        collateralList.push(collateral);
        underlyingToCollateral[underlying] = collateral;
        return address(collateral);
    }

    function setCollateralFeed(ICollateral collateral, address feed) public onlyOwner {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        oracle.setCollateralFeed(address(collateral.asset()), feed);
    }

    function setCollateralFactor(ICollateral collateral, uint collateralFactor) public onlyOwner {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        require(collateralFactor < 10000, "collateralFactorTooHigh");
        collateralsData[collateral].prevCollateralFactor = getCollateralFactor(collateral);
        collateralsData[collateral].lastCollateralFactorUpdate = block.timestamp;
        collateralsData[collateral].collateralFactorBps = collateralFactor;
    }

    function setCollateralHardCap(ICollateral collateral, uint hardCapUsd) public onlyOwner {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        collateralsData[collateral].prevHardCap = getHardCapUsd(collateral);
        collateralsData[collateral].hardCap = hardCapUsd;
        collateralsData[collateral].lastHardCapUpdate = block.timestamp;
    }

    function setCollateralSoftCap(ICollateral collateral, uint softCapBps) public onlyOwner {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        require(softCapBps <= MAX_SOFT_CAP, "softCapTooHigh");
        collateralsData[collateral].prevSoftCap = getSoftCapUsd(collateral);
        collateralsData[collateral].softCapBps = softCapBps;
        collateralsData[collateral].lastSoftCapUpdate = block.timestamp;
    }

    function updateCollateralFeeController() external {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "onlyCollaterals");
        uint capUsd = getCapUsd(collateral);
        uint price = oracle.getCollateralPriceMantissa(
            address(collateral),
            getCollateralFactor(collateral),
            collateral.totalAssets(),
            capUsd
        );
        collateralFeeController.update(address(collateral), price, capUsd);
    }

    function getSoftCapUsd(ICollateral collateral) public view returns (uint) {
        uint softCapBps = collateralsData[collateral].softCapBps;
        uint softCapTimeElapsed = block.timestamp - collateralsData[collateral].lastSoftCapUpdate;
        if(softCapTimeElapsed < 7 days) { // else use current soft cap
            uint prevSoftCap = collateralsData[collateral].prevSoftCap;
            uint currentWeight = softCapTimeElapsed;
            uint prevWeight = 7 days - currentWeight;
            softCapBps = (prevSoftCap * prevWeight + softCapBps * currentWeight) / 7 days;
        }
        return supplyEMASum * softCapBps / 10000;
    }

    function getHardCapUsd(ICollateral collateral) public view returns (uint) {
        uint hardCap = collateralsData[collateral].hardCap;
        uint hardCapTimeElapsed = block.timestamp - collateralsData[collateral].lastHardCapUpdate;
        if(hardCapTimeElapsed < 7 days) { // else use current hard cap
            uint prevHardCap = collateralsData[collateral].prevHardCap;
            uint currentWeight = hardCapTimeElapsed;
            uint prevWeight = 7 days - currentWeight;
            hardCap = (prevHardCap * prevWeight + hardCap * currentWeight) / 7 days;
        }
        return hardCap;
    }

    function getCollateralFactor(ICollateral collateral) public view returns (uint) {
        uint collateralFactorBps = collateralsData[collateral].collateralFactorBps;
        uint collateralFactorTimeElapsed = block.timestamp - collateralsData[collateral].lastCollateralFactorUpdate;
        if(collateralFactorTimeElapsed < 7 days) { // else use current collateral factor
            uint prevCollateralFactor = collateralsData[collateral].prevCollateralFactor;
            uint currentWeight = collateralFactorTimeElapsed;
            uint prevWeight = 7 days - currentWeight;
            collateralFactorBps = (prevCollateralFactor * prevWeight + collateralFactorBps * currentWeight) / 7 days;
        }
        return collateralFactorBps;
    }

    function getCapUsd(ICollateral collateral) public view returns (uint) {
        uint softCap = getSoftCapUsd(collateral);
        uint hardCap = getHardCapUsd(collateral);
        return hardCap < softCap ? hardCap : softCap;
    }

    function maxCollateralDeposit(ICollateral collateral) external view returns (uint) {
        if(collateralsData[collateral].enabled == false) return 0;
        if(collateralsData[collateral].depositPaused == true) return 0;
        uint capUsd = getCapUsd(collateral);
        uint totalAssets = collateral.totalAssets();
        // get oracle price
        uint price = oracle.viewCollateralPriceMantissa(
            address(collateral),
            getCollateralFactor(collateral),
            totalAssets,
            capUsd
        );
        uint totalValue = totalAssets * price / MANTISSA;
        if(totalValue >= capUsd) return 0;
        uint remainingValue = capUsd - totalValue;
        uint remainingDeposits = remainingValue * MANTISSA / price;
        return remainingDeposits;
    }

    function maxCollateralWithdraw(ICollateral collateral, address account) external view returns (uint) {
        if(collateralsData[collateral].enabled == false) return 0;
        if(collateralsData[collateral].depositPaused == true) return 0;
        
        uint bal = collateral.getCollateralOf(account);
        
        // calculate liabilities
        uint liabilitiesUsd = 0;
        for (uint i = 0; i < userPools[account].length; i++) {
            IPool pool = userPools[account][i];
            uint debt = pool.getDebtOf(account);
            uint price = oracle.viewDebtPriceMantissa(address(pool));
            uint debtUsd = debt * price / MANTISSA;
            liabilitiesUsd += debtUsd;
        }

        if(liabilitiesUsd == 0) return bal;

        // calculate assets
        uint assetsUsd = 0;
        for (uint i = 0; i < userCollaterals[account].length; i++) {
            ICollateral thisCollateral = userCollaterals[account][i];
            uint capUsd = getCapUsd(thisCollateral);
            uint price = oracle.viewCollateralPriceMantissa(
                address(thisCollateral),
                getCollateralFactor(thisCollateral),
                thisCollateral.totalAssets(),
                capUsd
            );
            uint thisCollateralBalance = collateral.getCollateralOf(account);
            uint thisCollateralUsd = thisCollateralBalance * getCollateralFactor(thisCollateral) * price / 10000 / MANTISSA;
            assetsUsd += thisCollateralUsd;
        }

        if(assetsUsd <= liabilitiesUsd) return 0;
        uint deltaUsd = assetsUsd - liabilitiesUsd;
        uint collateralFactorBps = getCollateralFactor(collateral);
        uint _capUsd = getCapUsd(collateral);
        uint _price = oracle.viewCollateralPriceMantissa(
            address(collateral),
            collateralFactorBps,
            collateral.totalAssets(),
            _capUsd
        );
        uint deltaCollateral = deltaUsd * MANTISSA * 10000 / _price / collateralFactorBps;
        uint maxCollateral = bal > deltaCollateral ? deltaCollateral : bal;
        return maxCollateral;
    }

    function onCollateralDeposit(address recipient, uint256 amount) external returns (bool) {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");
        require(collateralsData[collateral].depositPaused == false, "depositPaused");
        uint capUsd = getCapUsd(collateral);
        // get oracle price
        uint price = oracle.getCollateralPriceMantissa(
            address(collateral),
            getCollateralFactor(collateral),
            collateral.totalAssets(),
            capUsd
            );
        // enforce both caps
        uint totalCollateralAfter = collateral.totalAssets() + amount;
        uint totalValueAfter = totalCollateralAfter * price / MANTISSA;
        require(totalValueAfter <= capUsd, "capExceeded");
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
            for (uint i = 0; i < userCollaterals[caller].length; i++) {
                ICollateral thisCollateral = userCollaterals[caller][i];
                uint capUsd = getCapUsd(thisCollateral);
                uint collateralFactorBps = getCollateralFactor(thisCollateral);
                uint price = oracle.getCollateralPriceMantissa(
                    address(thisCollateral),
                    collateralFactorBps,
                    thisCollateral.totalAssets(),
                    capUsd
                );
                uint thisCollateralBalance = collateral.getCollateralOf(caller);
                if(thisCollateral == collateral) thisCollateralBalance -= amount;
                uint thisCollateralUsd = thisCollateralBalance * collateralFactorBps * price / 10000 / MANTISSA;
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

    function onCollateralReceive(address recipient) external returns (bool) {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");
        if(collateralUsers[collateral][recipient] == false) {
            collateralUsers[collateral][recipient] = true;
            userCollaterals[recipient].push(collateral);
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

    function onPoolDeposit(uint256 amount) external returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");
        uint totalAssets = pool.totalAssets();
        require(totalAssets + amount <= poolsData[pool].depositCap, "depositCapExceeded");
        updateTotalSuppliedValue(pool, totalAssets + amount);
        return true;
    }

    function onPoolWithdraw(uint256 amount) external returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");
        uint totalAssets = pool.totalAssets();
        totalAssets = totalAssets > amount ? totalAssets - amount : 0;
        updateTotalSuppliedValue(pool, totalAssets);
        return true;
    }

    function updateTotalSuppliedValue(IPool pool, uint totalAssets) internal {
        uint price = oracle.getDebtPriceMantissa(address(pool));
        uint totalValueUsd = totalAssets * price / MANTISSA;
        EMA.EMAState memory supplyEMA = poolsData[pool].supplyEMA;
        uint prevEMA = supplyEMA.ema;
        supplyEMA = supplyEMA.update(totalValueUsd, 7 days);
        poolsData[pool].supplyEMA = supplyEMA;
        supplyEMASum = supplyEMASum - prevEMA + supplyEMA.ema;
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
        for (uint i = 0; i < userCollaterals[caller].length; i++) {
            ICollateral thisCollateral = userCollaterals[caller][i];
            uint capUsd = getCapUsd(thisCollateral);
            uint collateralFactorBps = getCollateralFactor(thisCollateral);
            uint price = oracle.getCollateralPriceMantissa(
                address(thisCollateral),
                collateralFactorBps,
                thisCollateral.totalAssets(),
                capUsd
            );
            uint thisCollateralBalance = thisCollateral.getCollateralOf(caller);
            uint thisCollateralUsd = thisCollateralBalance * collateralFactorBps * price / 10000 / MANTISSA;
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

    function onPoolRepay(address recipient, uint256 amount) external returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");

        uint debt = pool.getDebtOf(recipient);

        // if user repays all, remove from userPools and poolUsers
        if(amount == debt) {
            for (uint i = 0; i < userPools[recipient].length; i++) {
                if(userPools[recipient][i] == pool) {
                    userPools[recipient][i] = userPools[recipient][userPools[recipient].length - 1];
                    userPools[recipient].pop();
                    break;
                }
            }
            poolUsers[pool][recipient] = false;
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
                    getCollateralFactor(collateral),
                    collateral.totalAssets(),
                    getCapUsd(collateral)
                ) / MANTISSA;

                for (uint i = 0; i < userCollaterals[borrower].length; i++) {
                    ICollateral thisCollateral = userCollaterals[borrower][i];
                    uint capUsd = getCapUsd(thisCollateral);
                    uint collateralFactorBps = getCollateralFactor(thisCollateral);
                    uint price = oracle.getCollateralPriceMantissa(
                        address(thisCollateral),
                        collateralFactorBps,
                        thisCollateral.totalAssets(),
                        capUsd
                    );
                    uint thisCollateralBalance = thisCollateral.getCollateralOf(borrower);
                    uint thisCollateralUsd = thisCollateralBalance * collateralFactorBps * price / 10000 / MANTISSA;
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
                getCollateralFactor(collateral),
                collateral.totalAssets(),
                getCapUsd(collateral)
            );
            uint collateralAmount = debtValue * MANTISSA / collateralPrice;
            uint collateralIncentive = collateralAmount * liquidationIncentiveBps / 10000;
            uint collateralIncentiveUsd = collateralIncentive * collateralPrice / MANTISSA;
            uint collateralReward = collateralAmount + collateralIncentive;
            
            // enforce max liquidation incentive
            require(collateralIncentiveUsd <= maxLiquidationIncentiveUsd, "maxLiquidationIncentiveExceeded");

            IERC20 debtToken = IERC20(address(pool.asset()));
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
        for (uint i = 0; i < userCollaterals[borrower].length; i++) {
            ICollateral thisCollateral = userCollaterals[borrower][i];
            uint capUsd = getCapUsd(thisCollateral);
            uint price = oracle.getCollateralPriceMantissa(
                address(thisCollateral),
                getCollateralFactor(thisCollateral),
                thisCollateral.totalAssets(),
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
            updateTotalSuppliedValue(thisPool, thisPool.totalAssets());
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