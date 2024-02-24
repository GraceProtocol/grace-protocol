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

contract MockGTR is ERC20 {
    function minters(address) external view returns (uint) {
        return type(uint).max;
    }
}

contract VaultFactoryTest is Test {

    MockGTR public gtr;
    VaultFactory vaultFactory;

    function setUp() public {
        gtr = new MockGTR();
        vaultFactory = new VaultFactory(address(gtr), address(0x1), 1000);
    }

    function test_constructor() public {
        assertEq(address(vaultFactory.gtr()), address(gtr));
        assertEq(vaultFactory.weth(), address(0x1));
        assertEq(vaultFactory.operator(), address(this));
        assertEq(vaultFactory.rewardBudget(), 1000);
    }

    function test_createVault() public {
        MockPool pool = new MockPool();

        vm.startPrank(address(1));
        vm.expectRevert("onlyOperator"); // not operator
        Vault(payable(vaultFactory.createVault(
            address(pool),
            1
        )));
        vm.stopPrank();

        Vault vault = Vault(payable(vaultFactory.createVault(
            address(pool),
            1
        )));

        assertEq(address(vault.pool()), address(pool));
        assertEq(vaultFactory.isVault(address(vault)), true);
        assertEq(vaultFactory.balanceOf(address(vault)), 1);
        assertEq(vaultFactory.totalSupply(), 1);
        assertEq(vaultFactory.allVaultsLength(), 1);
        assertEq(vaultFactory.allVaults(0), address(vault));
    }

    function test_setOperator() public {
        vaultFactory.setOperator(address(1));
        assertEq(vaultFactory.operator(), address(1));

        vm.expectRevert("onlyOperator"); // no longer operator
        vaultFactory.setOperator(address(0x2));
    }

    function test_setWeight() public {
        MockPool pool = new MockPool();
        Vault vault = Vault(payable(vaultFactory.createVault(
            address(pool),
            1
        )));
        assertEq(vaultFactory.balanceOf(address(vault)), 1);

        vaultFactory.setWeight(address(vault), 2);
        assertEq(vaultFactory.balanceOf(address(vault)), 2);

        vm.startPrank(address(1));
        vm.expectRevert("onlyOperator"); // not operator
        vaultFactory.setWeight(address(vault), 3);
        vm.stopPrank();
    }

    function test_claim() public {
        MockPool pool = new MockPool();
        Vault vault = Vault(payable(vaultFactory.createVault(
            address(pool),
            1
        )));

        skip(365 days);
        vm.prank(address(vault));
        vaultFactory.claim();
        assertEq(gtr.balanceOf(address(vault)), 1000);
    }

    function test_claimable() public {
        MockPool pool = new MockPool();
        Vault vault = Vault(payable(vaultFactory.createVault(
            address(pool),
            1
        )));

        assertEq(vaultFactory.claimable(address(vault)), 0);

        skip(365 days);
        assertEq(vaultFactory.claimable(address(vault)), 1000);

        vm.prank(address(vault));
        vaultFactory.claim();
        assertEq(vaultFactory.claimable(address(vault)), 0);        
    }

    function test_setBudget() public {

        MockPool pool = new MockPool();
        Vault vault = Vault(payable(vaultFactory.createVault(
            address(pool),
            1
        )));

        vm.startPrank(address(1));
        vm.expectRevert("onlyOperator"); // not operator
        vaultFactory.setBudget(2000);
        vm.stopPrank();

        vaultFactory.setBudget(2000);
        assertEq(vaultFactory.rewardBudget(), 2000);

        skip(365 days);
        assertEq(vaultFactory.claimable(address(vault)), 2000);
    }

}