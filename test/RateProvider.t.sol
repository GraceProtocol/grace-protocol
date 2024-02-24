// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/RateProvider.sol";

contract MockRateModel {
    uint public rateBps;
    uint public util;
    uint public lastRate;
    uint public lastAccrued;

    function setRateBps(uint _rateBps) public {
        rateBps = _rateBps;
    }

    function setExpectedValues(uint _util, uint _lastRate, uint _lastAccrued) public {
        util = _util;
        lastRate = _lastRate;
        lastAccrued = _lastAccrued;
    }

    function getRateBps(uint _util, uint _lastRate, uint _lastAccrued) public view returns (uint) {
        require(util == _util, "util");
        require(lastRate == _lastRate, "lastRate");
        require(lastAccrued == _lastAccrued, "lastAccrued");
        return rateBps;
    }

}

contract RateProviderTest is Test {

    RateProvider public rateProvider;

    function setUp() public {
        rateProvider = new RateProvider();
    }

    function test_constructor() public {
        assertEq(rateProvider.owner(), address(this));
    }

    function test_setOwner() public {
        rateProvider.setOwner(address(1));
        assertEq(rateProvider.owner(), address(1));
        vm.expectRevert("onlyOwner");
        rateProvider.setOwner(address(this));
        assertEq(rateProvider.owner(), address(1));
    }

    function test_setDefaultInterestRateModel() public {
        rateProvider.setDefaultInterestRateModel(address(1));
        assertEq(rateProvider.defaultInterestRateModel(), address(1));
        rateProvider.setOwner(address(1));
        vm.expectRevert("onlyOwner");
        rateProvider.setDefaultInterestRateModel(address(2));
        assertEq(rateProvider.defaultInterestRateModel(), address(1));
    }

    function test_setDefaultCollateralFeeModel() public {
        rateProvider.setDefaultCollateralFeeModel(address(1));
        assertEq(rateProvider.defaultCollateralFeeModel(), address(1));
        rateProvider.setOwner(address(1));
        vm.expectRevert("onlyOwner");
        rateProvider.setDefaultCollateralFeeModel(address(2));
        assertEq(rateProvider.defaultCollateralFeeModel(), address(1));
    }

    function test_setInterestRateModel() public {
        rateProvider.setInterestRateModel(address(1), address(2));
        assertEq(rateProvider.interestRateModels(address(1)), address(2));
        rateProvider.setOwner(address(1));
        vm.expectRevert("onlyOwner");
        rateProvider.setInterestRateModel(address(1), address(3));
        assertEq(rateProvider.interestRateModels(address(1)), address(2));
    }

    function test_setCollateralFeeModel() public {
        rateProvider.setCollateralFeeModel(address(1), address(2));
        assertEq(rateProvider.collateralFeeModels(address(1)), address(2));
        rateProvider.setOwner(address(1));
        vm.expectRevert("onlyOwner");
        rateProvider.setCollateralFeeModel(address(1), address(3));
        assertEq(rateProvider.collateralFeeModels(address(1)), address(2));
    }

    function test_getCollateralFeeModelOf() public {
        assertEq(rateProvider.getCollateralFeeModelOf(address(1)), address(0));
        rateProvider.setDefaultCollateralFeeModel(address(1));
        assertEq(rateProvider.getCollateralFeeModelOf(address(2)), address(1));
        rateProvider.setCollateralFeeModel(address(2), address(3));
        assertEq(rateProvider.getCollateralFeeModelOf(address(2)), address(3));
    }

    function test_getCollateralFeeModelFeeBps() public {
        MockRateModel model = new MockRateModel();
        rateProvider.setDefaultCollateralFeeModel(address(model));
        model.setRateBps(100);
        model.setExpectedValues(1, 2, 3);
        assertEq(rateProvider.getCollateralFeeModelFeeBps(address(model), 1, 2, 3), 100);
        model.setRateBps(200);
        assertEq(rateProvider.getCollateralFeeModelFeeBps(address(model), 1, 2, 3), 200);
        model.setRateBps(rateProvider.MAX_COLLATERAL_FEE_BPS());
        assertEq(rateProvider.getCollateralFeeModelFeeBps(address(model), 1, 2, 3), rateProvider.MAX_COLLATERAL_FEE_BPS());
        model.setRateBps(rateProvider.MAX_COLLATERAL_FEE_BPS() + 1);
        assertEq(rateProvider.getCollateralFeeModelFeeBps(address(model), 1, 2, 3), rateProvider.MAX_COLLATERAL_FEE_BPS());
    }

    function test_getInterestRateModelOf() public {
        assertEq(rateProvider.getInterestRateModelOf(address(1)), address(0));
        rateProvider.setDefaultInterestRateModel(address(1));
        assertEq(rateProvider.getInterestRateModelOf(address(2)), address(1));
        rateProvider.setInterestRateModel(address(2), address(3));
        assertEq(rateProvider.getInterestRateModelOf(address(2)), address(3));
    }

    function test_getInterestRateModelBorrowRate() public {
        MockRateModel model = new MockRateModel();
        rateProvider.setDefaultInterestRateModel(address(model));
        model.setRateBps(100);
        model.setExpectedValues(1, 2, 3);
        assertEq(rateProvider.getInterestRateModelBorrowRate(address(model), 1, 2, 3), 100);
        model.setRateBps(200);
        assertEq(rateProvider.getInterestRateModelBorrowRate(address(model), 1, 2, 3), 200);
        model.setRateBps(rateProvider.MAX_BORROW_RATE_BPS());
        assertEq(rateProvider.getInterestRateModelBorrowRate(address(model), 1, 2, 3), rateProvider.MAX_BORROW_RATE_BPS());
        model.setRateBps(rateProvider.MAX_BORROW_RATE_BPS() + 1);
        assertEq(rateProvider.getInterestRateModelBorrowRate(address(model), 1, 2, 3), rateProvider.MAX_BORROW_RATE_BPS());
    }
}