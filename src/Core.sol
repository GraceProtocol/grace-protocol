// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPoolDeployer {
    function deployPool(string memory name, string memory symbol, address underlying, bool isWETH) external returns (address pool);
}

interface ICollateralDeployer {
    function deployCollateral(address underlying, bool isWETH) external returns (address collateral);
}

interface IBorrowController {
    function onBorrow(address pool, address borrower, uint amount, uint price) external;
    function onRepay(address pool, address borrower, uint amount, uint price) external;
}

interface IOracle {
    function getCollateralPriceMantissa(address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) external returns (uint256);
    function getDebtPriceMantissa(address token) external returns (uint256);
    function viewCollateralPriceMantissa(address caller, address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) external view returns (uint256);
    function viewDebtPriceMantissa(address caller, address token) external view returns (uint256);
    function isDebtPriceFeedValid(address token) external view returns (bool);
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

    struct CollateralConfig {
        bool enabled;
        uint collateralFactorBps;
        uint capUsd;
        // cap variables
        uint lastCapUsdUpdate;
        uint prevCapUsd;
        // collateral factor variables
        uint lastCollateralFactorUpdate;
        uint prevCollateralFactor;
    }

    struct PoolConfig {
        bool enabled;
        uint depositCap;
    }

    struct LiquidationEvent {
        uint timestamp;
        address borrower;
        address liquidator;
        address pool;
        address collateral;
        uint debtAmount;
        uint collateralReward;
    }

    IPoolDeployer public poolDeployer;
    ICollateralDeployer public collateralDeployer;
    address public immutable WETH;
    uint public liquidationIncentiveBps = 1000; // 10%
    uint public maxLiquidationIncentiveUsd = 1000e18; // $1,000
    uint public badDebtCollateralThresholdUsd = 1000e18; // $1000
    uint public writeOffIncentiveBps = 2500; // 25%
    uint256 public lockDepth;
    address public owner;
    IOracle public oracle;
    IBorrowController public borrowController;
    IRateProvider public rateProvider;
    address public feeDestination = address(this);
    uint constant MANTISSA = 1e18;
    mapping (ICollateral => CollateralConfig) public collateralsData;
    mapping (IPool => PoolConfig) public poolsData;
    mapping (ICollateral => mapping (address => bool)) public collateralUsers;
    mapping (IPool => mapping (address => bool)) public poolBorrowers;
    mapping (address => ICollateral[]) public userCollaterals;
    mapping (address => IPool[]) public borrowerPools;
    IPool[] public poolList;
    ICollateral[] public collateralList;
    LiquidationEvent[] public liquidationEvents;

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
        uint size;
        assembly { size := extcodesize(underlying) }
        require(size > 0, "invalidUnderlying");
        bool isWETH = underlying == WETH;
        IPool pool = IPool(poolDeployer.deployPool(name, symbol, underlying, isWETH));
        poolsData[pool] = PoolConfig({
            enabled: true,
            depositCap: depositCap
        });
        poolList.push(pool);
        emit DeployPool(address(pool));
        return address(pool);
    }

    function setPoolDepositCap(IPool pool, uint depositCap) public onlyOwner {
        require(poolsData[pool].enabled == true, "poolNotAdded");
        poolsData[pool].depositCap = depositCap;
    }

    function deployCollateral(
        address underlying,
        uint collateralFactor,
        uint capUsd
    ) public onlyOwner returns (address) {
        require(collateralFactor < 10000, "collateralFactorTooHigh");
        uint size;
        assembly { size := extcodesize(underlying) }
        require(size > 0, "invalidUnderlying");
        bool isWETH = underlying == WETH;
        ICollateral collateral = ICollateral(collateralDeployer.deployCollateral(underlying, isWETH));
        collateralsData[collateral] = CollateralConfig({
            enabled: true,
            collateralFactorBps: collateralFactor,
            capUsd: capUsd,
            lastCapUsdUpdate: 0,
            prevCapUsd: 0,
            lastCollateralFactorUpdate: 0,
            prevCollateralFactor: 0
        });
        collateralList.push(collateral);
        emit DeployCollateral(address(collateral));
        return address(collateral);
    }

    function setCollateralFactor(ICollateral collateral, uint collateralFactor) public onlyOwner {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        require(collateralFactor < 10000, "collateralFactorTooHigh");
        collateralsData[collateral].prevCollateralFactor = getCollateralFactor(collateral);
        collateralsData[collateral].lastCollateralFactorUpdate = block.timestamp;
        collateralsData[collateral].collateralFactorBps = collateralFactor;
    }

    function setCollateralCapUsd(ICollateral collateral, uint capUsd) public onlyOwner {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        collateralsData[collateral].prevCapUsd = getCapUsd(collateral);
        collateralsData[collateral].capUsd = capUsd;
        collateralsData[collateral].lastCapUsdUpdate = block.timestamp;
    }

    function getCapUsd(ICollateral collateral) public view returns (uint) {
        uint capUsd = collateralsData[collateral].capUsd;
        uint capUsdTimeElapsed = block.timestamp - collateralsData[collateral].lastCapUsdUpdate;
        if(capUsdTimeElapsed < 7 days) { // else use current cap
            uint prevCapUsd = collateralsData[collateral].prevCapUsd;
            uint currentWeight = capUsdTimeElapsed;
            uint prevWeight = 7 days - currentWeight;
            // calculate weighted average based on time elapsed, the more time elapsed, the more weight to new value
            capUsd = (prevCapUsd * prevWeight + capUsd * currentWeight) / 7 days;
        }
        return capUsd;
    }

    function getCollateralFactor(ICollateral collateral) public view returns (uint) {
        uint collateralFactorBps = collateralsData[collateral].collateralFactorBps;
        uint collateralFactorTimeElapsed = block.timestamp - collateralsData[collateral].lastCollateralFactorUpdate;
        if(collateralFactorTimeElapsed < 7 days) { // else use current collateral factor
            uint prevCollateralFactor = collateralsData[collateral].prevCollateralFactor;
            uint currentWeight = collateralFactorTimeElapsed;
            uint prevWeight = 7 days - currentWeight;
            // calculate weighted average based on time elapsed, the more time elapsed, the more weight to new value
            collateralFactorBps = (prevCollateralFactor * prevWeight + collateralFactorBps * currentWeight) / 7 days;
        }
        return collateralFactorBps;
    }

    function viewCollateralPriceMantissa(ICollateral collateral) external view returns (uint256) {
        require(collateralsData[collateral].enabled == true, "collateralNotAdded");
        uint capUsd = getCapUsd(collateral);
        return oracle.viewCollateralPriceMantissa(
            address(this),
            collateral.asset(),
            getCollateralFactor(collateral),
            collateral.totalAssets(),
            capUsd
        );
    }

    function viewDebtPriceMantissa(IPool pool) external view returns (uint256) {
        require(poolsData[pool].enabled == true, "poolNotAdded");
        return oracle.viewDebtPriceMantissa(address(this), pool.asset());
    }

    function onCollateralDeposit(address recipient, uint256 amount) external returns (bool) {
        ICollateral collateral = ICollateral(msg.sender);
        require(collateralsData[collateral].enabled, "collateralNotEnabled");
        uint capUsd = getCapUsd(collateral);
        // get oracle price
        uint price = oracle.getCollateralPriceMantissa(
            collateral.asset(),
            getCollateralFactor(collateral),
            collateral.totalAssets(),
            capUsd
            );
        // enforce cap
        uint totalCollateralAfter = collateral.totalAssets() + amount;
        uint totalValueAfter = totalCollateralAfter * price / MANTISSA;
        require(totalValueAfter < capUsd, "capExceeded");
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
        uint borrowerPoolsLength = borrowerPools[caller].length;
        for (uint i = 0; i < borrowerPoolsLength; i++) {
            IPool pool = borrowerPools[caller][i];
            // borrower must repay any debt with invalid price feeds before withdrawing any collateral
            require(oracle.isDebtPriceFeedValid(pool.asset()), "invalidPriceFeed");
            uint debt = pool.getDebtOf(caller);
            uint price = oracle.getDebtPriceMantissa(pool.asset());
            uint debtUsd = debt * price / MANTISSA;
            liabilitiesUsd += debtUsd;
        }

        // calculate assets
        uint assetsUsd = 0;
        uint userCollateralsLength = userCollaterals[caller].length;
        // if liabilities == 0, skip assets check to save gas
        if(liabilitiesUsd > 0) {
            for (uint i = 0; i < userCollateralsLength; i++) {
                ICollateral thisCollateral = userCollaterals[caller][i];
                uint capUsd = getCapUsd(thisCollateral);
                uint collateralFactorBps = getCollateralFactor(thisCollateral);
                uint price = oracle.getCollateralPriceMantissa(
                    thisCollateral.asset(),
                    collateralFactorBps,
                    thisCollateral.totalAssets(),
                    capUsd
                );
                uint thisCollateralBalance = thisCollateral.getCollateralOf(caller);
                if(thisCollateral == collateral) thisCollateralBalance -= amount;
                // apply collateral factor before adding to assets
                uint thisCollateralUsd = thisCollateralBalance * collateralFactorBps * price / 10000 / MANTISSA;
                assetsUsd += thisCollateralUsd;
            }
        }

        // check if assets are greater than liabilities
        require(assetsUsd >= liabilitiesUsd, "insufficientAssets");

        // if user withdraws full collateral, remove from userCollaterals and collateralUsers
        if(amount == collateral.getCollateralOf(caller)) {
            for (uint i = 0; i < userCollateralsLength; i++) {
                if(userCollaterals[caller][i] == collateral) {
                    userCollaterals[caller][i] = userCollaterals[caller][userCollateralsLength - 1];
                    userCollaterals[caller].pop();
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
            ICollateral(collateral).asset(),
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

    function onPoolDeposit(uint256 amount) external view returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");
        uint totalAssets = pool.totalAssets();
        require(totalAssets + amount <= poolsData[pool].depositCap, "depositCapExceeded");
        return true;
    }

    function onPoolBorrow(address caller, uint256 amount) external returns (bool) {
        IPool pool = IPool(msg.sender);
        require(poolsData[pool].enabled, "notPool");
        // if first borrow, add to borrowerPools and poolBorrowers
        if(poolBorrowers[pool][caller] == false) {
            poolBorrowers[pool][caller] = true;
            borrowerPools[caller].push(pool);
        }

        // calculate assets
        uint assetsUsd = 0;
        uint userCollateralsLength = userCollaterals[caller].length;
        for (uint i = 0; i < userCollateralsLength; i++) {
            ICollateral thisCollateral = userCollaterals[caller][i];
            uint capUsd = getCapUsd(thisCollateral);
            uint collateralFactorBps = getCollateralFactor(thisCollateral);
            uint price = oracle.getCollateralPriceMantissa(
                thisCollateral.asset(),
                collateralFactorBps,
                thisCollateral.totalAssets(),
                capUsd
            );
            uint thisCollateralBalance = thisCollateral.getCollateralOf(caller);
            // apply collateral factor before adding to assets
            uint thisCollateralUsd = thisCollateralBalance * collateralFactorBps * price / 10000 / MANTISSA;
            assetsUsd += thisCollateralUsd;
        }

        // calculate liabilities
        uint liabilitiesUsd = 0;
        uint borrowerPoolsLength = borrowerPools[caller].length;
        for (uint i = 0; i < borrowerPoolsLength; i++) {
            IPool thisPool = borrowerPools[caller][i];
            // borrower must repay any debt with invalid price feeds before borrowing more
            require(oracle.isDebtPriceFeedValid(thisPool.asset()), "invalidPriceFeed");
            uint debt = thisPool.getDebtOf(caller);
            if(thisPool == pool) debt += amount;
            uint price = oracle.getDebtPriceMantissa(thisPool.asset());
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
            uint borrowerPoolsLength = borrowerPools[recipient].length;
            for (uint i = 0; i < borrowerPoolsLength; i++) {
                if(borrowerPools[recipient][i] == pool) {
                    borrowerPools[recipient][i] = borrowerPools[recipient][borrowerPoolsLength - 1];
                    borrowerPools[recipient].pop();
                    break;
                }
            }
            poolBorrowers[pool][recipient] = false;
        }

        if(borrowController != IBorrowController(address(0))) {
            borrowController.onRepay(msg.sender, recipient, amount, oracle.getDebtPriceMantissa(pool.asset()));
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

    function poolCount() external view returns (uint) {
        return poolList.length;
    }

    function collateralCount() external view returns (uint) {
        return collateralList.length;
    }

    function liquidationEventsCount() external view returns (uint) {
        return liquidationEvents.length;
    }

    function userCollateralsCount(address user) external view returns (uint) {
        return userCollaterals[user].length;
    }

    function borrowerPoolsCount(address user) external view returns (uint) {
        return borrowerPools[user].length;
    }

    function liquidate(address borrower, IPool pool, ICollateral collateral, uint debtAmount) lock external {
        require(collateralUsers[collateral][borrower], "notCollateralUser");
        require(poolBorrowers[pool][borrower], "notPoolBorrower");
        require(debtAmount > 0, "zeroDebtAmount");
        if(debtAmount == type(uint256).max) debtAmount = pool.getDebtOf(borrower);
        {
            uint liabilitiesUsd;
            {
                uint poolDebtUsd = pool.getDebtOf(borrower) * oracle.getDebtPriceMantissa(pool.asset()) / MANTISSA;
                // calculate liabilities
                liabilitiesUsd = poolDebtUsd;
                uint borrowerPoolsLength = borrowerPools[borrower].length;
                for (uint i = 0; i < borrowerPoolsLength; i++) {
                    IPool thisPool = borrowerPools[borrower][i];
                    if (thisPool != pool) {
                        uint debt = thisPool.getDebtOf(borrower);
                        uint price = oracle.getDebtPriceMantissa(thisPool.asset());
                        uint debtUsd = debt * price / MANTISSA;
                        // only the pool with the most debt can be repaid
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
                    collateral.asset(),
                    getCollateralFactor(collateral),
                    collateral.totalAssets(),
                    getCapUsd(collateral)
                ) / MANTISSA;

                uint userCollateralsLength = userCollaterals[borrower].length;
                for (uint i = 0; i < userCollateralsLength; i++) {
                    ICollateral thisCollateral = userCollaterals[borrower][i];
                    uint capUsd = getCapUsd(thisCollateral);
                    uint collateralFactorBps = getCollateralFactor(thisCollateral);
                    uint price = oracle.getCollateralPriceMantissa(
                        thisCollateral.asset(),
                        collateralFactorBps,
                        thisCollateral.totalAssets(),
                        capUsd
                    );
                    uint thisCollateralBalance = thisCollateral.getCollateralOf(borrower);
                    uint thisCollateralUsd = thisCollateralBalance * price / MANTISSA;
                    if(thisCollateral != collateral) {
                        // only the most valuable collateral can be seized
                        require(thisCollateralUsd <= collateralBalanceUsd, "notMostValuableCollateral");
                    }
                    // apply collateral factor before adding to assets
                    assetsUsd += thisCollateralUsd * collateralFactorBps / 10000;
                }
            }
            require(assetsUsd < liabilitiesUsd, "insufficientLiabilities");
        }

        {
            // calculate collateral reward
            uint debtPrice = oracle.getDebtPriceMantissa(pool.asset());
            uint debtValue = debtAmount * debtPrice / MANTISSA;
            uint collateralPrice = oracle.getCollateralPriceMantissa(
                collateral.asset(),
                getCollateralFactor(collateral),
                collateral.totalAssets(),
                getCapUsd(collateral)
            );
            uint collateralAmount = debtValue * MANTISSA / collateralPrice;
            // add an incentive for the liquidator as an additional percentage of the collateral amount
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
            liquidationEvents.push(LiquidationEvent({
                timestamp: block.timestamp,
                borrower: borrower,
                liquidator: msg.sender,
                pool: address(pool),
                collateral: address(collateral),
                debtAmount: debtAmount,
                collateralReward: collateralReward
            }));
            emit Liquidate(borrower, address(pool), address(collateral), debtAmount, collateralReward);
        }

        if(collateral.getCollateralOf(borrower) == 0) {
            // remove from userCollaterals and collateralUsers
            uint userCollateralsLength = userCollaterals[borrower].length;
            for (uint i = 0; i < userCollateralsLength; i++) {
                if(userCollaterals[borrower][i] == collateral) {
                    userCollaterals[borrower][i] = userCollaterals[borrower][userCollateralsLength - 1];
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
        uint borrowerPoolsLength = borrowerPools[borrower].length;
        for (uint i = 0; i < borrowerPoolsLength; i++) {
            IPool thisPool = borrowerPools[borrower][i];
            uint debt = thisPool.getDebtOf(borrower);
            uint price = oracle.getDebtPriceMantissa(thisPool.asset());
            uint debtUsd = debt * price / MANTISSA;
            liabilitiesUsd += debtUsd;
        }

        require(liabilitiesUsd > 0, "noLiabilities");

        // calculate assets, without applying collateral factor
        uint assetsUsd = 0;
        uint userCollateralsLength = userCollaterals[borrower].length;
        for (uint i = 0; i < userCollateralsLength; i++) {
            ICollateral thisCollateral = userCollaterals[borrower][i];
            uint capUsd = getCapUsd(thisCollateral);
            uint price = oracle.getCollateralPriceMantissa(
                thisCollateral.asset(),
                getCollateralFactor(thisCollateral),
                thisCollateral.totalAssets(),
                capUsd
            );
            uint thisCollateralBalance = thisCollateral.getCollateralOf(borrower);
            uint thisCollateralUsd = thisCollateralBalance * price / MANTISSA;
            // check if collateral balance is below bad debt threshold, otherwise we wait for more liquidations to occur
            require(thisCollateralUsd < badDebtCollateralThresholdUsd, "collateralBalanceTooHigh");
            assetsUsd += thisCollateralUsd;
        }

        require(assetsUsd < liabilitiesUsd, "insufficientLiabilities");

        // write off
        for (uint i = 0; i < borrowerPoolsLength; i++) {
            IPool thisPool = borrowerPools[borrower][i];
            thisPool.writeOff(borrower);
            poolBorrowers[thisPool][borrower] = false;
        }
        delete borrowerPools[borrower];

        // seize
        for (uint i = 0; i < userCollateralsLength; i++) {
            ICollateral thisCollateral = userCollaterals[borrower][i];
            uint thisCollateralBalance = thisCollateral.getCollateralOf(borrower);
            // calculate reward as a percentage of the collateral balance to incentivize the caller
            uint reward = thisCollateralBalance * writeOffIncentiveBps / 10000;
            uint fee = thisCollateralBalance - reward;
            if(fee > 0) thisCollateral.seize(borrower, fee, feeDestination);
            if(reward > 0) thisCollateral.seize(borrower, type(uint).max, msg.sender);
            collateralUsers[thisCollateral][borrower] = false;
        }
        delete userCollaterals[borrower];

        emit WriteOff(borrower);
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

    event DeployCollateral(address indexed collateral);
    event DeployPool(address indexed pool);
    event Liquidate(address indexed borrower, address indexed pool, address indexed collateral, uint debtAmount, uint collateralReward);
    event WriteOff(address indexed borrower);

}