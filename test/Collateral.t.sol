// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/Collateral.sol";
import "./mocks/ERC20.sol";
import "./mocks/MockCore.sol";

contract CollateralTest is Test, MockCore {

    Collateral public collateral;
    ERC20 public asset;

    function setUp() public {
        asset = new ERC20();
        collateral = new Collateral(
            "Collateral",
            "COL",
            ICollateralUnderlying(address(asset)),
            address(this)
        );
    }

    function test_constructor() public {
        assertEq(collateral.name(), "Collateral");
        assertEq(collateral.symbol(), "COL");
        assertEq(collateral.decimals(), 18);
        assertEq(address(collateral.asset()), address(asset));
        assertEq(address(collateral.core()), address(this));
    }

    function test_deposit() public {
        asset.mint(address(this), 1000);
        asset.approve(address(collateral), 1000);
        collateral.deposit(1000, address(this));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);   
        assertEq(collateral.getCollateralOf(address(this)), 1000);  
    }

    function test_mint() public {
        asset.mint(address(this), 1000);
        asset.approve(address(collateral), 1000);
        collateral.mint(1000, address(this));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
    }

    function test_withdraw() public {
        asset.mint(address(this), 2000);
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        collateral.withdraw(2000, address(this), address(this));
        collateral.withdraw(1000, address(this), address(this));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
    }

    function test_redeem() public {
        asset.mint(address(this), 2000);
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        collateral.redeem(2000, address(this), address(this));
        collateral.redeem(1000, address(this), address(this));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
    }

    function test_transfer() public {
        asset.mint(address(this), 1000);
        asset.approve(address(collateral), 1000);
        collateral.deposit(1000, address(this));
        collateral.transfer(address(1), 1000);
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(1)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(1)), 1000);  
    }

    function test_approve_transferFrom() public {
        asset.mint(address(this), 1000);
        asset.approve(address(collateral), 1000);
        collateral.deposit(1000, address(this));
        collateral.approve(address(1), 1000);
        assertEq(collateral.allowance(address(this), address(1)), 1000);
        vm.prank(address(1));
        collateral.transferFrom(address(this), address(1), 1000);
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(1)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(1)), 1000);  
    }

    function test_seize() public {
        asset.mint(address(this), 2000);
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(1));
        vm.expectRevert("minimumBalance");
        collateral.seize(address(1), 2000, address(this));
        collateral.seize(address(1), 1000, address(this));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(asset.balanceOf(address(this)), 1000);
        assertEq(collateral.balanceOf(address(1)), 1000);
        assertEq(collateral.balanceOf(address(this)), 0);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(1)), 1000);  
    }

    function test_pull() public {
        asset.mint(address(this), 1000);
        asset.approve(address(collateral), 1000);
        collateral.deposit(1000, address(this));
        vm.expectRevert("cannotPullUnderlying");
        collateral.pull(address(asset), address(1), 1000);
        ERC20 stuckToken = new ERC20();
        stuckToken.mint(address(collateral), 1000);
        collateral.pull(address(stuckToken), address(this), 1000);
        assertEq(stuckToken.balanceOf(address(collateral)), 0);
        assertEq(stuckToken.balanceOf(address(this)), 1000);
    }

    function test_invalidateNonce() public {
        assertEq(collateral.nonces(address(this)), 0);
        collateral.invalidateNonce();
        assertEq(collateral.nonces(address(this)), 1);
    }

    function test_accrueFee() public {
        asset.mint(address(this), 10000);
        asset.approve(address(collateral), 10000);
        collateral.deposit(10000, address(this));
        vm.warp(block.timestamp + (365 days / 2));
        assertEq(collateral.getCollateralOf(address(this)), 5000);
        assertEq(collateral.totalAssets(), 5000);
        assertEq(collateral.totalSupply(), 10000);
        collateral.withdraw(1000, address(this), address(this));
        assertEq(collateral.getCollateralOf(address(this)), 4000);
        assertEq(collateral.totalAssets(), 4000);
        assertEq(collateral.totalSupply(), 9000);
        vm.warp(block.timestamp + 365 days);
        // should not go below minimumBalance
        assertEq(collateral.getCollateralOf(address(this)), 1000);
        assertEq(collateral.totalAssets(), 1000);
        vm.expectRevert("minimumBalance");
        collateral.withdraw(1000, address(this), address(this));
    }

}