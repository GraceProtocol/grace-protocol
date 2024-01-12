// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./EMA.sol";

interface IPoolDeployer {
    function deployPool(string memory name, string memory symbol, address underlying) external returns (address pool);
}

interface ICollateralDeployer {
    function deployCollateral(string memory name, string memory symbol, address underlying, bool isWETH) external returns (address collateral);
}

interface IBorrowController {
    function onBorrow(address pool, address borrower, uint amount, uint price) external;
    function onRepay(address pool, address borrower, uint amount, uint price) external;
}

interface IOracle {
    function getCollateralPriceMantissa(address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) external returns (uint256);
    function getDebtPriceMantissa(address token) external returns (uint256);
    function viewCollateralPriceMantissa(address caller, address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) external view returns (uint256);
}

interface IRateProvider {
    function getCollateralFeeModelFeeBps(address collateral, uint util, uint lastBorrowRate, uint lastAccrued) external view returns (uint256);
    function getInterestRateModelBorrowRate(address pool, uint util, uint lastBorrowRate, uint lastAccrued) external view returns (uint256);
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

contract Core {

    using SafeERC20 for IERC20;
    using EMA for EMA.EMAState;

    struct CollateralConfig {
        bool enabled;
        uint collateralFactorBps;
        uint hardCap;
        uint softCapBps;
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
        EMA.EMAState supplyEMA;
    }

    IPoolDeployer public poolDeployer;
    ICollateralDeployer public collateralDeployer;
    address public immutable WETH;
    uint public liquidationIncentiveBps = 1000; // 10%
    uint public maxLiquidationIncentiveUsd = 1000e18; // $1,000
    uint public badDebtCollateralThresholdUsd = 1000e18; // $1000
    uint public writeOffIncentiveBps = 1000; // 10%
    uint public supplyEMASum;
    uint256 public lockDepth;
    address public owner;
    IOracle public oracle;
    IBorrowController public borrowController;
    IRateProvider public rateProvider;
    address public feeDestination = address(this);
    uint constant MANTISSA = 1e18;
    uint public dailyBorrowLimitUsd = 100000e18; // $100,000
    uint public dailyBorrowLimitLastUpdate;
    uint public lastDailyBorrowLimitRemainingUsd = 100000e18; // $100,000
    mapping (ICollateral => CollateralConfig) public collateralsData;
    mapping (IPool => PoolConfig) public poolsData;
    mapping (address => IPool) public underlyingToPool;
    mapping (address => ICollateral) public underlyingToCollateral;
    mapping (ICollateral => mapping (address => bool)) public collateralUsers;
    mapping (IPool => mapping (address => bool)) public poolBorrowers;
    mapping (address => ICollateral[]) public userCollaterals;
    mapping (address => uint) public userCollateralsCount;
    mapping (address => IPool[]) public borrowerPools;
    mapping (address => uint) public borrowerPoolsCount;
    IPool[] public poolList;
    uint public poolCount;
    ICollateral[] public collateralList;
    uint public collateralCount;

    constructor(
        address _rateProvider,
        address _borrowController,
        address _oracle,
        address _poolDeployer,
        address _collateralDeployer,
        address _WETH
    ) {
        owner = msg.sender;
        rateProvider = IRateProvider(_rateProvider);
        borrowController = IBorrowController(_borrowController);
        oracle = IOracle(_oracle);
        poolDeployer = IPoolDeployer(_poolDeployer);
        collateralDeployer = ICollateralDeployer(_collateralDeployer);
        WETH = _WETH;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    function setOwner(address _owner) public onlyOwner { owner = _owner; }
    function setOracle(address _oracle) public onlyOwner { oracle = IOracle(_oracle); }
    function setBorrowController(address _borrowController) public onlyOwner { borrowController = IBorrowController(_borrowController); }
    function setRateProvider(address _rateProvider) public onlyOwner { rateProvider = IRateProvider(_rateProvider); }
    function setPoolDeployer(address _poolDeployer) public onlyOwner { poolDeployer = IPoolDeployer(_poolDeployer); }
    function setCollateralDeployer(address _collateralDeployer) public onlyOwner { collateralDeployer = ICollateralDeployer(_collateralDeployer); }
    function setFeeDestination(address _feeDestination) public onlyOwner { feeDestination = _feeDestination; }
    function setLiquidationIncentiveBps(uint _liquidationIncentiveBps) public onlyOwner {
        require(_liquidationIncentiveBps <= 10000, "liquidationIncentiveTooHigh");
        liquidationIncentiveBps = _liquidationIncentiveBps;
    }
    function setMaxLiquidationIncentiveUsd(uint _maxLiquidationIncentiveUsd) public onlyOwner { maxLiquidationIncentiveUsd = _maxLiquidationIncentiveUsd; }
    function setBadDebtCollateralThresholdUsd(uint _badDebtCollateralThresholdUsd) public onlyOwner { badDebtCollateralThresholdUsd = _badDebtCollateralThresholdUsd; }
    function setWriteOffIncentiveBps(uint _writeOffIncentiveBps) public onlyOwner {
        require(_writeOffIncentiveBps <= 10000, "writeOffIncentiveTooHigh");
        writeOffIncentiveBps = _writeOffIncentiveBps;
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

    function deployPool(
        string memory name,
        string memory symbol,
        address underlying,
        uint depositCap
    ) public onlyOwner returns (address) {
        require(underlyingToPool[underlying] == IPool(address(0)), "underlyingAlreadyAdded");
        uint size;
        assembly { size := extcodesize(underlying) }
        require(size > 0, "invalidUnderlying");
        IPool pool = IPool(poolDeployer.deployPool(name, symbol, underlying));
        EMA.EMAState memory emaState;
        emaState.lastUpdate = block.timestamp;
        poolsData[pool] = PoolConfig({
            enabled: true,
            depositCap: depositCap,
            supplyEMA: emaState
        });
        poolList.push(pool);
        poolCount++;
        underlyingToPool[underlying] = pool;
        return address(pool);
    }

    function setPoolDepositCap(IPool pool, uint depositCap) public onlyOwner {
        require(poolsData[pool].enabled == true, "poolNotAdded");
        poolsData[pool].depositCap = depositCap;
    }

    function deployCollateral(
        string memory name,
        string memory symbol,
        address underlying,
        uint collateralFactor,
        uint hardCapUsd,
        uint softCapBps
    ) public onlyOwner returns (address) {
        require(underlyingToCollateral[underlying] == ICollateral(address(0)), "underlyingAlreadyAdded");
        require(collateralFactor < 10000, "collateralFactorTooHigh");
        require(softCapBps <= 10000, "softCapTooHigh");
        uint size;
        assembly { size := extcodesize(underlying) }
        require(size > 0, "invalidUnderlying");
        bool isWETH = underlying == WETH;
        ICollateral collateral = ICollateral(collateralDeployer.deployCollateral(name, symbol, underlying, isWETH));
        collateralsData[collateral] = CollateralConfig({
            enabled: true,
            collateralFactorBps: collateralFactor,
            hardCap: hardCapUsd,
            softCapBps: softCapBps,
            lastSoftCapUpdate: block.timestamp,
            prevSoftCap: 0,
            lastHardCapUpdate: block.timestamp,
            prevHardCap: 0,
            lastCollateralFactorUpdate: block.timestamp,
            prevCollateralFactor: 0
        });
        collateralList.push(collateral);
        collateralCount++;
        underlyingToCollateral[underlying] = collateral;
        return address(collateral);
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
        require(softCapBps <= 10000, "softCapTooHigh");
        collateralsData[collateral].prevSoftCap = getSoftCapUsd(collateral);
        collateralsData[collateral].softCapBps = softCapBps;
        collateralsData[collateral].lastSoftCapUpdate = block.timestamp;
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

    function onCollateralDeposit(address recipient, uint256 amount) external returns (bool) {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");
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
            userCollateralsCount[recipient]++;
        }
        return true;
    }

    function onCollateralWithdraw(address caller, uint256 amount) external returns (bool) {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");

        // calculate liabilities
        uint liabilitiesUsd = 0;
        for (uint i = 0; i < borrowerPools[caller].length; i++) {
            IPool pool = borrowerPools[caller][i];
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
                    userCollateralsCount[caller]--;
                    break;
                }
            }
            collateralUsers[collateral][caller] = false;
        }
        return true;
    }

    function getCollateralFeeBps(address collateral, uint lastFee, uint lastAccrued) external view returns (uint256) {
        uint capUsd = getCapUsd(ICollateral(collateral));
        uint price = oracle.viewCollateralPriceMantissa(
            address(this),
            collateral,
            getCollateralFactor(ICollateral(collateral)),
            ICollateral(collateral).totalAssets(),
            capUsd
        );
        uint depositedUsd = ICollateral(collateral).totalAssets() * price / MANTISSA;
        uint util = capUsd > 0 ? depositedUsd * 10000 / capUsd : 10000;
        uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
        try rateProvider.getCollateralFeeModelFeeBps{gas:passedGas}(collateral, util, lastFee, lastAccrued) returns (uint256 _feeBps) {
            return _feeBps;
        } catch {
            return 0;
        }
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
        // if first borrow, add to borrowerPools and poolBorrowers
        if(poolBorrowers[pool][caller] == false) {
            poolBorrowers[pool][caller] = true;
            borrowerPools[caller].push(pool);
            borrowerPoolsCount[caller]++;
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
        for (uint i = 0; i < borrowerPools[caller].length; i++) {
            IPool thisPool = borrowerPools[caller][i];
            uint debt = thisPool.getDebtOf(caller);
            if(thisPool == pool) debt += amount;
            uint price = oracle.getDebtPriceMantissa(address(thisPool));
            uint debtUsd = debt * price / MANTISSA;
            if(thisPool == pool) {
                if(borrowController != IBorrowController(address(0))) {
                    borrowController.onBorrow(msg.sender, caller, amount, price);
                }
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

        // if user repays all, remove from borrowerPools and poolBorrowers
        if(amount == debt) {
            for (uint i = 0; i < borrowerPools[recipient].length; i++) {
                if(borrowerPools[recipient][i] == pool) {
                    borrowerPools[recipient][i] = borrowerPools[recipient][borrowerPools[recipient].length - 1];
                    borrowerPools[recipient].pop();
                    borrowerPoolsCount[recipient]--;
                    break;
                }
            }
            poolBorrowers[pool][recipient] = false;
        }

        if(borrowController != IBorrowController(address(0))) {
            borrowController.onRepay(msg.sender, recipient, amount, oracle.getDebtPriceMantissa(msg.sender));
        }
        return true;
    }

    function getBorrowRateBps(address pool, uint util, uint lastBorrowRate, uint lastAccrued) external view returns (uint256) {        
        uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
        try rateProvider.getInterestRateModelBorrowRate{gas: passedGas}(pool, util, lastBorrowRate, lastAccrued) returns (uint256 _borrowRateBps) {
            return _borrowRateBps;
        } catch {
            return 0;
        }
    }

    function liquidate(address borrower, IPool pool, ICollateral collateral, uint debtAmount) lock external {
        require(collateralUsers[collateral][borrower], "notCollateralUser");
        require(poolBorrowers[pool][borrower], "notPoolBorrower");
        require(debtAmount > 0, "zeroDebtAmount");
        if(debtAmount == type(uint256).max) debtAmount = pool.getDebtOf(borrower);
        {
            uint liabilitiesUsd;
            {
                uint poolDebtUsd = pool.getDebtOf(borrower) * oracle.getDebtPriceMantissa(address(pool)) / MANTISSA;
                // calculate liabilities
                liabilitiesUsd = poolDebtUsd;
                for (uint i = 0; i < borrowerPools[borrower].length; i++) {
                    IPool thisPool = borrowerPools[borrower][i];
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
            debtToken.safeTransferFrom(msg.sender, address(this), debtAmount);
            debtToken.forceApprove(address(pool), debtAmount);
            pool.repay(borrower, debtAmount);
            collateral.seize(borrower, collateralReward, msg.sender);
        }

        if(collateral.getCollateralOf(borrower) == 0) {
            // remove from userCollaterals and collateralUsers
            for (uint i = 0; i < userCollaterals[borrower].length; i++) {
                if(userCollaterals[borrower][i] == collateral) {
                    userCollaterals[borrower][i] = userCollaterals[borrower][userCollaterals[borrower].length - 1];
                    userCollaterals[borrower].pop();
                    userCollateralsCount[borrower]--;
                    break;
                }
            }
            collateralUsers[collateral][borrower] = false;
        }
    }

    function writeOff(address borrower) public lock {
        // calculate liabilities
        uint liabilitiesUsd = 0;
        for (uint i = 0; i < borrowerPools[borrower].length; i++) {
            IPool thisPool = borrowerPools[borrower][i];
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
        for (uint i = 0; i < borrowerPools[borrower].length; i++) {
            IPool thisPool = borrowerPools[borrower][i];
            uint totalAssets = thisPool.totalAssets(); // to use previous pool lastBalance
            uint debt = thisPool.getDebtOf(borrower);
            thisPool.writeOff(borrower);
            updateTotalSuppliedValue(thisPool, totalAssets - debt);
            poolBorrowers[thisPool][borrower] = false;
        }
        delete borrowerPools[borrower];
        borrowerPoolsCount[borrower] = 0;

        // seize
        for (uint i = 0; i < userCollaterals[borrower].length; i++) {
            ICollateral thisCollateral = userCollaterals[borrower][i];
            uint thisCollateralBalance = thisCollateral.getCollateralOf(borrower);
            uint reward = thisCollateralBalance * writeOffIncentiveBps / 10000;
            uint fee = thisCollateralBalance - reward;
            if(fee > 0) thisCollateral.seize(borrower, fee, feeDestination);
            if(reward > 0) thisCollateral.seize(borrower, reward, msg.sender);
            collateralUsers[thisCollateral][borrower] = false;
        }
        delete userCollaterals[borrower];
        userCollateralsCount[borrower] = 0;
    }

    function pullFromCore(IERC20 token, address dst, uint amount) public onlyOwner {
        token.safeTransfer(dst, amount);
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