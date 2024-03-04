// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Core.sol";
import {PoolDeployer} from "../src/PoolDeployer.sol";
import {CollateralDeployer} from "../src/CollateralDeployer.sol";
import "./mocks/ERC20.sol";
import {Collateral} from "../src/Collateral.sol";
import {Pool} from "../src/Pool.sol";

contract MockRateProvider {

}

contract MockBorrowController {
    function onBorrow(address /*pool*/, address /*borrower*/, uint /*amount*/, uint /*price*/) external {}
    function onRepay(address /*pool*/, address /*borrower*/, uint /*amount*/, uint /*price*/) external {}

}

contract MockOracle {

    address public expectedCaller;
    address public expectedToken;
    uint public expectedCollateralFactorBps;
    uint public expectedTotalCollateral;
    uint public expectedCapUsd;
    bool public skipChecks;

    function setSkipChecks(bool skip) public {
        skipChecks = skip;
    }

    function setExpectedValues(address caller, address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) public {
        expectedCaller = caller;
        expectedToken = token;
        expectedCollateralFactorBps = collateralFactorBps;
        expectedTotalCollateral = totalCollateral;
        expectedCapUsd = capUsd;
    }

    function viewCollateralPriceMantissa(address caller, address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) external view returns (uint) {
        if(!skipChecks) {
            require(caller == expectedCaller, "caller");
            require(token == expectedToken, "token");
            require(expectedCollateralFactorBps == collateralFactorBps, "collateralFactorBps");
            require(totalCollateral == expectedTotalCollateral, "totalCollateral");
            require(capUsd == expectedCapUsd, "capUsd");
        }
        return 1e18;
    }

    function getCollateralPriceMantissa(address token, uint collateralFactorBps, uint totalCollateral, uint capUsd) external returns (uint) {
        if(!skipChecks) {
            require(msg.sender == expectedCaller, "caller");
            require(token == expectedToken, "token");
            require(expectedCollateralFactorBps == collateralFactorBps, "collateralFactorBps");
            require(totalCollateral == expectedTotalCollateral, "totalCollateral");
            require(capUsd == expectedCapUsd, "capUsd");
        }
        return 1e18;
    }

    function viewDebtPriceMantissa(address caller, address token) external view returns (uint) {
        if(!skipChecks) {
            require(caller == expectedCaller, "caller");
            require(token == expectedToken, "token");
        }
        return 1e18;
    }

    function getDebtPriceMantissa(address token) external returns (uint) {
        if(!skipChecks) {
            require(msg.sender == expectedCaller, "caller");
            require(token == expectedToken, "token");
        }
        return 1e18;
        return 1e18;
    }
}

contract MockWETH is ERC20 {
    function deposit() external payable {
        mint(msg.sender, msg.value);
    }

    function withdraw(uint amount) external {
        burnFrom(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
    
}

contract CoreTest is Test {

    MockRateProvider public rateProvider;
    MockBorrowController public borrowController;
    MockOracle public oracle;
    MockWETH public weth;
    PoolDeployer public poolDeployer;
    CollateralDeployer public collateralDeployer;
    Core public core;

    function setUp() public {
        rateProvider = new MockRateProvider();
        borrowController = new MockBorrowController();
        oracle = new MockOracle();
        weth = new MockWETH();
        poolDeployer = new PoolDeployer();
        collateralDeployer = new CollateralDeployer();
        core = new Core(
            address(rateProvider),
            address(borrowController),
            address(oracle),
            address(poolDeployer),
            address(collateralDeployer),
            address(weth)
        );
    }

    function test_constructor() public {
        assertEq(core.owner(), address(this));
        assertEq(address(core.rateProvider()), address(rateProvider));
        assertEq(address(core.borrowController()), address(borrowController));
        assertEq(address(core.oracle()), address(oracle));
        assertEq(address(core.poolDeployer()), address(poolDeployer));
        assertEq(address(core.collateralDeployer()), address(collateralDeployer));
        assertEq(address(core.WETH()), address(weth));
    }

    function test_setOwner() public {
        core.setOwner(address(1));
        assertEq(core.owner(), address(1));
        vm.expectRevert("onlyOwner");
        core.setOwner(address(this));
        assertEq(core.owner(), address(1));
    }

    function test_setOracle() public {
        core.setOracle(address(1));
        assertEq(address(core.oracle()), address(1));

        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setOracle(address(1));
        assertEq(address(core.oracle()), address(1));
    }

    function test_setBorrowController() public {
        core.setBorrowController(address(1));
        assertEq(address(core.borrowController()), address(1));

        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setBorrowController(address(1));
        assertEq(address(core.borrowController()), address(1));
    }

    function test_setRateProvider() public {
        core.setRateProvider(address(1));
        assertEq(address(core.rateProvider()), address(1));

        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setRateProvider(address(1));
        assertEq(address(core.rateProvider()), address(1));
    }

    function test_setPoolDeployer() public {
        core.setPoolDeployer(address(1));
        assertEq(address(core.poolDeployer()), address(1));

        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setPoolDeployer(address(1));
        assertEq(address(core.poolDeployer()), address(1));
    }

    function test_setCollateralDeployer() public {
        core.setCollateralDeployer(address(1));
        assertEq(address(core.collateralDeployer()), address(1));

        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setCollateralDeployer(address(1));
        assertEq(address(core.collateralDeployer()), address(1));
    }

    function test_setFeeDestination() public {
        core.setFeeDestination(address(1));
        assertEq(core.feeDestination(), address(1));

        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setFeeDestination(address(1));
        assertEq(core.feeDestination(), address(1));
    }

    function test_setLiquidationIncentiveBps() public {
        core.setLiquidationIncentiveBps(1000);
        assertEq(core.liquidationIncentiveBps(), 1000);

        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setLiquidationIncentiveBps(1000);
        assertEq(core.liquidationIncentiveBps(), 1000);
        vm.stopPrank();

        vm.expectRevert("liquidationIncentiveTooHigh");
        core.setLiquidationIncentiveBps(10001);
    }

    function test_setMaxLiquidationIncentiveUsd() public {
        core.setMaxLiquidationIncentiveUsd(1000);
        assertEq(core.maxLiquidationIncentiveUsd(), 1000);

        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setMaxLiquidationIncentiveUsd(1000);
        assertEq(core.maxLiquidationIncentiveUsd(), 1000);
    }

    function test_setBadDebtCollateralThresholdUsd() public {
        core.setBadDebtCollateralThresholdUsd(1000);
        assertEq(core.badDebtCollateralThresholdUsd(), 1000);

        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setBadDebtCollateralThresholdUsd(1000);
        assertEq(core.badDebtCollateralThresholdUsd(), 1000);
    }

    function test_setWriteOffIncentiveBps() public {
        core.setWriteOffIncentiveBps(1000);
        assertEq(core.writeOffIncentiveBps(), 1000);

        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setWriteOffIncentiveBps(1000);
        assertEq(core.writeOffIncentiveBps(), 1000);
        vm.stopPrank();

        vm.expectRevert("writeOffIncentiveTooHigh");
        core.setWriteOffIncentiveBps(10001);
    }

    function test_globalLockUnlockAsPool() public {
        address pool = core.deployPool("TEST", "TEST", address(new ERC20()), 1);
        vm.startPrank(address(pool));
        core.globalLock(address(1));
        assertEq(core.lockDepth(), 1);
        vm.expectRevert("locked");
        core.globalLock(address(1));
        core.globalLock(address(core)); // core caller is exempt
        assertEq(core.lockDepth(), 2);
        core.globalUnlock();
        assertEq(core.lockDepth(), 1);
        core.globalUnlock();
        assertEq(core.lockDepth(), 0);
    }

    function test_globalLockUnlockAsCollateral() public {
        address collateral = core.deployCollateral(address(new ERC20()), 0, 0);
        vm.startPrank(address(collateral));
        core.globalLock(address(1));
        assertEq(core.lockDepth(), 1);
        vm.expectRevert("locked");
        core.globalLock(address(1));
        core.globalLock(address(core)); // core caller is exempt
        assertEq(core.lockDepth(), 2);
        core.globalUnlock();
        assertEq(core.lockDepth(), 1);
        core.globalUnlock();
        assertEq(core.lockDepth(), 0);
    }

    function test_globalLockUnlockAsUnauthorized() public {
        vm.expectRevert("onlyCollateralsOrPools");
        core.globalLock(address(1));
        vm.expectRevert("onlyCollateralsOrPools");
        core.globalUnlock();
    }

    function test_setPoolDepositCap() public {
        address pool = core.deployPool("TEST", "TEST", address(new ERC20()), 1);
        core.setPoolDepositCap(IPool(pool), 1000);
        (, uint depositCap) = core.poolsData(IPool(pool));
        assertEq(depositCap, 1000);

        vm.startPrank(address(pool));
        vm.expectRevert("onlyOwner");
        core.setPoolDepositCap(IPool(pool), 1000);
    }

    function test_deployCollateralBadCollateralFactor() public {
        address underlying = address(new ERC20());
        uint CF = 10000;
        uint capUsd = 1000e18;
        vm.expectRevert("collateralFactorTooHigh");
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );

        CF = 9999;
        collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
    }


    function test_deployCollateralInvalidUnderlying() public {
        address underlying = address(0);
        uint CF = 9999;
        uint capUsd = 1000e18;
        vm.expectRevert("invalidUnderlying");
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );

        underlying = address(new ERC20());
        collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
    }

    function test_deployCollateralWeth() public {
        uint CF = 9999;
        uint capUsd = 1000e18;
        address collateral = core.deployCollateral(
            address(weth),
            CF,
            capUsd
        );
        assertEq(Collateral(payable(collateral)).isWETH(), true);

        collateral = core.deployCollateral(
            address(new ERC20()),
            CF,
            capUsd
        );
        assertEq(Collateral(payable(collateral)).isWETH(), false);
    }

    function test_deployCollateralUnauthorized() public {
        vm.startPrank(address(1));
        address underlying = address(new ERC20());
        vm.expectRevert("onlyOwner");
        core.deployCollateral(
            underlying,
            9999,
            1000e18
        );
    }

    function test_deployCollateral() public {
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
        assertEq(address(Collateral(payable(collateral)).asset()), underlying);
        (bool enabled, uint collateralFactor, uint cap, , , ,) = core.collateralsData(ICollateral(collateral));
        assertEq(enabled, true);
        assertEq(collateralFactor, CF);
        assertEq(cap, capUsd);
        assertEq(address(core.collateralList(0)), collateral);
    }

    function test_deployPoolInvalidUnderlying() public {
        address underlying = address(0);
        vm.expectRevert("invalidUnderlying");
        core.deployPool("TEST", "TEST", underlying, 1);
    }

    function test_deployPoolUnauthorized() public {
        vm.startPrank(address(1));
        address underlying = address(new ERC20());
        vm.expectRevert("onlyOwner");
        core.deployPool("TEST", "TEST", underlying, 1);
    }

    function test_deployPoolWeth() public {
        address underlying = address(weth);
        address pool = core.deployPool("TEST", "TEST", underlying, 1);
        assertEq(Pool(payable(pool)).isWETH(), true);

        underlying = address(new ERC20());
        pool = core.deployPool("TEST", "TEST", underlying, 1);
        assertEq(Pool(payable(pool)).isWETH(), false);
    }

    function test_deployPool() public {
        address underlying = address(new ERC20());
        uint depositCap = 1000;
        address pool = core.deployPool("TEST", "TEST", underlying, depositCap);
        assertEq(Pool(payable(pool)).name(), "TEST");
        assertEq(Pool(payable(pool)).symbol(), "TEST");
        assertEq(address(Pool(payable(pool)).asset()), underlying);
        assertEq(address(core.poolList(0)), pool);
        (bool enabled, uint depositCap_) = core.poolsData(IPool(pool));
        assertEq(enabled, true);
        assertEq(depositCap_, depositCap);
    }

    function test_setCollateralFactor() public {
        skip(7 days);
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
        core.setCollateralFactor(ICollateral(collateral), 1);
        (, uint collateralFactor, , , ,uint lastCollateralFactorUpdate , uint prevCollateralFactor) = core.collateralsData(ICollateral(collateral));
        assertEq(collateralFactor, 1);
        assertEq(lastCollateralFactorUpdate, block.timestamp);
        assertEq(prevCollateralFactor, 9999);
        assertEq(core.getCollateralFactor(ICollateral(collateral)), 9999); // not updated yet

        // wait 3.5 days
        skip(3.5 days);
        assertEq(core.getCollateralFactor(ICollateral(collateral)), 5000); // half way updated

        // wait 7 days
        skip(3.5 days);
        assertEq(core.getCollateralFactor(ICollateral(collateral)), 1); // fully updated
    }

    function test_setCollateralFactorUnauthorized() public {
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setCollateralFactor(ICollateral(collateral), 1);
    }

    function test_setCollateralFactorTooHigh() public {
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
        vm.expectRevert("collateralFactorTooHigh");
        core.setCollateralFactor(ICollateral(collateral), 10000);
    }

    function test_setCollateralFactorInexistentCollateral() public {
        vm.expectRevert("collateralNotAdded");
        core.setCollateralFactor(ICollateral(address(1)), 1);
    }

    function test_setCollateralCapUsd() public {
        skip(7 days);
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
        core.setCollateralCapUsd(ICollateral(collateral), 10000e18);
        (, , uint cap, uint lastCapUsdUpdate, uint prevCapUsd, ,) = core.collateralsData(ICollateral(collateral));
        assertEq(cap, 10000e18);
        assertEq(lastCapUsdUpdate, block.timestamp);
        assertEq(prevCapUsd, 1000e18);
        assertEq(core.getCapUsd(ICollateral(collateral)), 1000e18); // not updated yet

        // wait 3.5 days
        skip(3.5 days);
        assertEq(core.getCapUsd(ICollateral(collateral)), 5500e18); // half way updated

        // wait 7 days
        skip(3.5 days);
        assertEq(core.getCapUsd(ICollateral(collateral)), 10000e18); // fully updated
    }

    function test_setCollateralCapUsdUnauthorized() public {
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        core.setCollateralCapUsd(ICollateral(collateral), 10000e18);
    }

    function test_setCollateralCapUsdInexistentCollateral() public {
        vm.expectRevert("collateralNotAdded");
        core.setCollateralCapUsd(ICollateral(address(1)), 10000e18);
    }

    function test_viewCollateralPriceMantissa() public {
        skip(7 days);
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
        oracle.setExpectedValues(address(core), underlying, CF, 0, 1000e18);
        assertEq(core.viewCollateralPriceMantissa(ICollateral(collateral)), 1e18);
    }

    function test_viewCollateralPriceMantissaInexistentCollateral() public {
        vm.expectRevert();
        core.viewCollateralPriceMantissa(ICollateral(address(1)));
    }

    function test_viewDebtPriceMantissa() public {
        skip(7 days);
        address underlying = address(new ERC20());
        address pool = core.deployPool("TEST", "TEST", underlying, 1);
        oracle.setExpectedValues(address(core), underlying, 0, 0, 0);
        assertEq(core.viewDebtPriceMantissa(IPool(pool)), 1e18);
    }

    function test_viewDebtPriceMantissaInexistentPool() public {
        vm.expectRevert();
        core.viewDebtPriceMantissa(IPool(address(1)));
    }

    function test_onCollateralDepositBelowCap() public {
        skip(7 days);
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address recipient = address(1);
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
        oracle.setExpectedValues(address(core), underlying, CF, 0, capUsd);
        vm.startPrank(collateral);
        core.onCollateralDeposit(recipient, 999e18);
        assertEq(core.collateralUsers(ICollateral(collateral), recipient), true);
        assertEq(address(core.userCollaterals(recipient, 0)), collateral);
        assertEq(core.userCollateralsCount(recipient), 1);

        core.onCollateralDeposit(recipient, 999e18); // should be added once
        assertEq(core.userCollateralsCount(recipient), 1);
    }

    function test_onCollateralDepositAtCap() public {
        skip(7 days);
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address recipient = address(1);
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
        vm.startPrank(collateral);
        oracle.setExpectedValues(address(core), underlying, CF, 0, capUsd);
        vm.expectRevert("capExceeded");
        core.onCollateralDeposit(recipient, 1000e18);
    }

    function test_onCollateralWithdrawNoLoans() public {
        skip(7 days);
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address recipient = address(1);
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );
        vm.startPrank(collateral);
        oracle.setExpectedValues(address(core), underlying, CF, 0, capUsd);
        core.onCollateralDeposit(recipient, 999e18);
        vm.mockCall(
            collateral,
            abi.encodeWithSelector(Collateral.getCollateralOf.selector, recipient),
            abi.encode(999e18)
        );
        core.onCollateralWithdraw(recipient, 999e18);
        assertEq(core.collateralUsers(ICollateral(collateral), recipient), false);
        assertEq(core.userCollateralsCount(recipient), 0);
    }

    function test_onCollateralWithdrawWithLoans() public {
        skip(7 days);

        // deploy collateral
        address underlying = address(new ERC20());
        uint CF = 9999;
        uint capUsd = 1000e18;
        address recipient = address(1);
        address collateral = core.deployCollateral(
            underlying,
            CF,
            capUsd
        );

        // deploy pool
        address pool = core.deployPool("TEST", "TEST", underlying, type(uint).max);

        // deposit collateral
        vm.startPrank(collateral);
        oracle.setExpectedValues(address(core), underlying, CF, 0, capUsd);
        core.onCollateralDeposit(recipient, 999e18);

        // simulate collateral balance
        vm.mockCall(
            collateral,
            abi.encodeWithSelector(Collateral.getCollateralOf.selector, recipient),
            abi.encode(999e18)
        );

        // add pool to user's borrow list
        vm.startPrank(pool);
        core.onPoolBorrow(recipient, 500e18);

        // simulate debt
        vm.mockCall(
            pool,
            abi.encodeWithSelector(Pool.getDebtOf.selector, recipient),
            abi.encode(500e18)
        );

        vm.startPrank(collateral);
        vm.expectRevert("insufficientAssets");
        core.onCollateralWithdraw(recipient, 499e18);

        // success case
        core.onCollateralWithdraw(recipient, 498e18);
        // should still have the collateral
        assertEq(core.collateralUsers(ICollateral(collateral), recipient), true);
        assertEq(core.userCollateralsCount(recipient), 1);
    }

    function test_onPoolDepositAtDepositCap() public {
        skip(7 days);
        address underlying = address(new ERC20());
        address pool = core.deployPool("TEST", "TEST", underlying, 1000e18);
        vm.startPrank(pool);
        core.onPoolDeposit(1000e18);
    }

    function test_onPoolDepositAboveDepositCap() public {
        skip(7 days);
        address underlying = address(new ERC20());
        address pool = core.deployPool("TEST", "TEST", underlying, 1000e18);
        vm.startPrank(pool);
        vm.expectRevert("depositCapExceeded");
        core.onPoolDeposit(1000e18 + 1);
    }

    function test_onPoolBorrowNoCollateral() public {
        skip(7 days);
        address underlying = address(new ERC20());
        address pool = core.deployPool("TEST", "TEST", underlying, 1000e18);
        vm.mockCall(
            pool,
            abi.encodeWithSelector(Pool.getDebtOf.selector, address(1)),
            abi.encode(1000e18)
        );
        oracle.setExpectedValues(address(core), underlying, 0, 0, 0);
        vm.startPrank(pool);
        vm.expectRevert("insufficientAssets");
        core.onPoolBorrow(address(1), 1000e18);
    }

    function test_onPoolBorrowSufficientCollateral() public {
        skip(7 days);
        address underlying = address(new ERC20());
        address collateral = core.deployCollateral(underlying, 5000, type(uint).max);
        address pool = core.deployPool("TEST", "TEST", underlying, 1000e18);
        ERC20(payable(underlying)).mint(address(this), 2000e18);
        ERC20(payable(underlying)).approve(collateral, 1000e18);

        // deposit collateral
        oracle.setSkipChecks(true); // skip checks for the next line because totalCollateral changes mid-tx
        Collateral(payable(collateral)).deposit(1000e18);
        oracle.setSkipChecks(false);

        // lend
        ERC20(payable(underlying)).approve(pool, 1000e18);
        Pool(payable(pool)).deposit(1000e18);

        // borrow
        oracle.setExpectedValues(address(core), underlying, 5000, 1000e18, type(uint).max);
        Pool(payable(pool)).borrow(500e18);
        assertEq(core.poolBorrowers(IPool(pool), address(this)), true);
        assertEq(address(core.borrowerPools(address(this), 0)), pool);
    }

    function test_onPoolBorrowInsufficientCollateral() public {
        skip(7 days);
        address underlying = address(new ERC20());
        address collateral = core.deployCollateral(underlying, 5000, type(uint).max);
        address pool = core.deployPool("TEST", "TEST", underlying, 1000e18);
        ERC20(payable(underlying)).mint(address(this), 2000e18);
        ERC20(payable(underlying)).approve(collateral, 1000e18);

        // deposit collateral
        oracle.setSkipChecks(true); // skip checks for the next line because totalCollateral changes mid-tx
        Collateral(payable(collateral)).deposit(1000e18);
        oracle.setSkipChecks(false);

        // lend
        ERC20(payable(underlying)).approve(pool, 1000e18);
        Pool(payable(pool)).deposit(1000e18);

        // borrow
        oracle.setExpectedValues(address(core), underlying, 5000, 1000e18, type(uint).max);
        vm.expectRevert("insufficientAssets");
        Pool(payable(pool)).borrow(501e18);
    }

    function test_onPoolRepayFull() public {
        skip(7 days);
        address underlying = address(new ERC20());
        address collateral = core.deployCollateral(underlying, 5000, type(uint).max);
        address pool = core.deployPool("TEST", "TEST", underlying, 1000e18);
        ERC20(payable(underlying)).mint(address(this), 2000e18);
        ERC20(payable(underlying)).approve(collateral, 1000e18);

        // deposit collateral
        oracle.setSkipChecks(true); // skip checks for the next line because totalCollateral changes mid-tx
        Collateral(payable(collateral)).deposit(1000e18);
        oracle.setSkipChecks(false);

        // lend
        ERC20(payable(underlying)).approve(pool, 1000e18);
        Pool(payable(pool)).deposit(1000e18);

        // borrow
        oracle.setExpectedValues(address(core), underlying, 5000, 1000e18, type(uint).max);
        Pool(payable(pool)).borrow(500e18);
        assertEq(core.poolBorrowers(IPool(pool), address(this)), true);
        assertEq(address(core.borrowerPools(address(this), 0)), pool);

        // repay
        ERC20(payable(underlying)).approve(pool, 500e18);
        Pool(payable(pool)).repay(500e18);
        assertEq(core.poolBorrowers(IPool(pool), address(this)), false);
        assertEq(core.borrowerPoolsCount(address(this)), 0);
    }

    function test_onPoolRepayPartial() public {
        skip(7 days);
        address underlying = address(new ERC20());
        address collateral = core.deployCollateral(underlying, 5000, type(uint).max);
        address pool = core.deployPool("TEST", "TEST", underlying, 1000e18);
        ERC20(payable(underlying)).mint(address(this), 2000e18);
        ERC20(payable(underlying)).approve(collateral, 1000e18);

        // deposit collateral
        oracle.setSkipChecks(true); // skip checks for the next line because totalCollateral changes mid-tx
        Collateral(payable(collateral)).deposit(1000e18);
        oracle.setSkipChecks(false);

        // lend
        ERC20(payable(underlying)).approve(pool, 1000e18);
        Pool(payable(pool)).deposit(1000e18);

        // borrow
        oracle.setExpectedValues(address(core), underlying, 5000, 1000e18, type(uint).max);
        Pool(payable(pool)).borrow(500e18);
        assertEq(core.poolBorrowers(IPool(pool), address(this)), true);
        assertEq(address(core.borrowerPools(address(this), 0)), pool);

        // repay
        ERC20(payable(underlying)).approve(pool, 499e18);
        Pool(payable(pool)).repay(499e18);
        assertEq(core.poolBorrowers(IPool(pool), address(this)), true);
        assertEq(core.borrowerPoolsCount(address(this)), 1);
        assertEq(address(core.borrowerPools(address(this), 0)), pool);
    }

}