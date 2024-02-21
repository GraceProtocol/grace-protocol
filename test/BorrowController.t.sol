// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/BorrowController.sol";

contract BorrowControllerWrapper is BorrowController {
    function _updateDailyBorrowLimit() public {
        updateDailyBorrowLimit();
    }

    function setLastDailyBorrowLimitRemainingUsd(address _user, uint _amount) public {
        lastDailyBorrowLimitRemainingUsd[_user] = _amount;
    }
}

contract BorrowControllerTest is Test {

    BorrowControllerWrapper public borrowController;

    function setUp() public {
        borrowController = new BorrowControllerWrapper();
    }

    function test_constructor() public {
        assertEq(borrowController.owner(), address(this));
    }

    function test_setOwner() public {
        borrowController.setOwner(address(1));
        assertEq(borrowController.owner(), address(1));
        vm.expectRevert("onlyOwner");
        borrowController.setOwner(address(this));
        assertEq(borrowController.owner(), address(1));
    }

    function test_setGuardian() public {
        borrowController.setGuardian(address(1));
        assertEq(borrowController.guardian(), address(1));
        vm.startPrank(address(2));
        vm.expectRevert("onlyOwner");
        borrowController.setGuardian(address(this));
        assertEq(borrowController.guardian(), address(1));
    }

    function test_setPoolBorrowPaused() public {
        // not guardian
        vm.expectRevert("onlyGuardian");
        borrowController.setPoolBorrowPaused(address(1), true);
        
        // success case
        borrowController.setGuardian(address(this));
        borrowController.setPoolBorrowPaused(address(1), true);
        assert(borrowController.isPoolBorrowPaused(address(1)));
        borrowController.setPoolBorrowPaused(address(1), false);
        assert(!borrowController.isPoolBorrowPaused(address(1)));

        // suspended
        borrowController.setPoolBorrowSuspended(address(1), true);
        vm.expectRevert("borrowSuspended");
        borrowController.setPoolBorrowPaused(address(1), true);
    }

    function test_setForbidContracts() public {
        borrowController.setForbidContracts(false);
        assert(!borrowController.forbidContracts());
        borrowController.onBorrow(address(1), address(1), 1, 1);
        borrowController.setForbidContracts(true);
        assert(borrowController.forbidContracts());
        vm.expectRevert("contractNotAllowed");
        borrowController.onBorrow(address(1), address(1), 1, 1);

        // not owner
        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        borrowController.setForbidContracts(false);
    }

    function test_setContractAllowed() public {
        borrowController.setForbidContracts(true);
        borrowController.setContractAllowed(address(1), true);
        assertEq(borrowController.isContractAllowed(address(1)), true);
        borrowController.onBorrow(address(1), address(1), 1, 1);
        borrowController.setContractAllowed(address(1), false);
        assertEq(borrowController.isContractAllowed(address(1)), false);
        vm.expectRevert("contractNotAllowed");
        borrowController.onBorrow(address(1), address(1), 1, 1);

        // not owner
        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        borrowController.setContractAllowed(address(1), true);
    }

    function test_setPoolBorrowSuspended() public {
        // suspend
        borrowController.setPoolBorrowSuspended(address(1), true);
        assertEq(borrowController.isPoolBorrowSuspended(address(1)), true);
        assertEq(borrowController.isPoolBorrowPaused(address(1)), true);
        borrowController.setGuardian(address(this));
        vm.expectRevert("borrowSuspended");
        borrowController.setPoolBorrowPaused(address(1), false);

        // unsuspend
        borrowController.setPoolBorrowSuspended(address(1), false);
        assertEq(borrowController.isPoolBorrowSuspended(address(1)), false);
        assertEq(borrowController.isPoolBorrowPaused(address(1)), true); // still paused after unsuspend

        // not owner
        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");
        borrowController.setPoolBorrowSuspended(address(1), true);
    }

    function test_setDailyBorrowLimitUsd() public {
        borrowController.setDailyBorrowLimitUsd(1000);
        assertEq(borrowController.dailyBorrowLimitUsd(), 1000);

        // not owner
        vm.startPrank(address(1));
        vm.expectRevert("onlyOwner");   
        borrowController.setDailyBorrowLimitUsd(1000);
    }

    function test_updateDailyBorrowLimit() public {
        uint limit = borrowController.dailyBorrowLimitUsd();
        
        // first call
        vm.warp(1 days);
        borrowController._updateDailyBorrowLimit();
        assertEq(borrowController.lastDailyBorrowLimitRemainingUsd(address(this)), limit);
        
        // consume limit then wait half day
        borrowController.setLastDailyBorrowLimitRemainingUsd(address(this), 0);
        vm.warp(1.5 days);
        borrowController._updateDailyBorrowLimit();
        assertEq(borrowController.lastDailyBorrowLimitRemainingUsd(address(this)), limit / 2);

        // full day
        vm.warp(2 days);
        borrowController._updateDailyBorrowLimit();
        assertEq(borrowController.lastDailyBorrowLimitRemainingUsd(address(this)), limit);

        // 2 days
        vm.warp(3 days);
        borrowController._updateDailyBorrowLimit();
        assertEq(borrowController.lastDailyBorrowLimitRemainingUsd(address(this)), limit);
    }

    function test_onBorrowPaused() public {
        borrowController.setGuardian(address(this));
        borrowController.setPoolBorrowPaused(address(1), true);
        vm.expectRevert("borrowPaused");
        borrowController.onBorrow(address(1), address(1), 1, 1);
    }

    function test_onBorrowForbidContracts() public {
        borrowController.setForbidContracts(true);
        vm.expectRevert("contractNotAllowed");
        borrowController.onBorrow(address(1), address(1), 1, 1);
    }

    function test_onBorrowAllowedContract() public {
        borrowController.setForbidContracts(true);
        borrowController.setContractAllowed(address(1), true);
        borrowController.onBorrow(address(1), address(1), 1, 1);
    }

    function test_onBorrowDailyLimit() public {
        vm.warp(1 days);
        borrowController.setDailyBorrowLimitUsd(1000);
        borrowController.setForbidContracts(false);
        borrowController.onBorrow(address(1), address(1), 1, 1e18);
        assertEq(borrowController.lastDailyBorrowLimitRemainingUsd(address(this)), 1000 - 1);
    }

    function test_onRepay() public {
        vm.warp(1 days);
        borrowController.setDailyBorrowLimitUsd(1000);
        borrowController.setForbidContracts(false);
        borrowController.onBorrow(address(1), address(1), 1, 1e18);
        assertEq(borrowController.lastDailyBorrowLimitRemainingUsd(address(this)), 1000 - 1);
        borrowController.onRepay(address(1), address(1), 1, 1e18);
        assertEq(borrowController.lastDailyBorrowLimitRemainingUsd(address(this)), 1000);
    }

    function test_onRepayLargerThanLimit() public {
        vm.warp(1 days);
        borrowController.setDailyBorrowLimitUsd(1000);
        borrowController.setForbidContracts(false);
        borrowController.onBorrow(address(1), address(1), 1, 1e18);
        assertEq(borrowController.lastDailyBorrowLimitRemainingUsd(address(this)), 1000 - 1);
        borrowController.setLastDailyBorrowLimitRemainingUsd(address(this), 1000);
        borrowController.onRepay(address(1), address(1), 1, 1e18);
        assertEq(borrowController.lastDailyBorrowLimitRemainingUsd(address(this)), 1000);
    }

}