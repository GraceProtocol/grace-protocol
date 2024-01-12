// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/VaultFactory.sol";
import "../src/Vault.sol";
import "./mocks/ERC20.sol";

contract MockPool is ERC20 {
    
    ERC20 public asset;

    constructor() {
        asset = new ERC20();
    }
}

contract VaultFactoryTest is Test {

    ERC20 public gtr;
    VaultFactory vaultFactory;

    function setUp() public {
        gtr = new ERC20();
        vaultFactory = new VaultFactory(address(gtr), address(0x1));
    }

    function test_constructor() public {
        assertEq(address(vaultFactory.gtr()), address(gtr));
        assertEq(vaultFactory.operator(), address(this));
    }

    function test_createVault() public {

        uint initialRewardBudget = 1000;

        MockPool pool = new MockPool();

        Vault vault = Vault(vaultFactory.createVault(
            address(pool),
            initialRewardBudget
        ));

        assertEq(vaultFactory.allVaultsLength(), 1);
        assertEq(vaultFactory.allVaults(0), address(vault));

        assertEq(address(vault.pool()), address(pool));
        assertEq(vault.rewardBudget(), initialRewardBudget);
    }

    function test_setOperator() public {
        vaultFactory.setOperator(address(1));
        assertEq(vaultFactory.operator(), address(1));

        vm.expectRevert("onlyOperator"); // no longer operator
        vaultFactory.setOperator(address(0x2));
    }

    function test_transferReward() public {
        MockPool pool = new MockPool();
        address vault = vaultFactory.createVault(
            address(pool),
            1000
        );

        vm.expectRevert("onlyVault"); // not vault
        vaultFactory.transferReward(address(1), 100);
        vm.prank(vault);
        vaultFactory.transferReward(address(1), 100);
        assertEq(gtr.balanceOf(address(1)), 100);
    }

    function test_setBudget() public {
        MockPool pool = new MockPool();
        address vault = vaultFactory.createVault(
            address(pool),
            1000
        );

        vm.startPrank(address(1));
        vm.expectRevert("onlyOperator"); // not operator
        vaultFactory.setBudget(vault, 100);
        vm.stopPrank();
        assertEq(Vault(vault).rewardBudget(), 1000);
        vaultFactory.setBudget(vault, 100);
        assertEq(Vault(vault).rewardBudget(), 100);
        vm.expectRevert("onlyVault"); // not vault
        vaultFactory.setBudget(address(1), 100);
    }

}