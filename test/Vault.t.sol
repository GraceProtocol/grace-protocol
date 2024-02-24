// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "./mocks/ERC20.sol";

contract MockFactory {

    ERC20 public gtr;
    uint _claimable;

    constructor(ERC20 _gtr) {
        gtr = _gtr;
    }

    function setClaimable(uint value) public {
        _claimable = value;
    }

    function claimable(address) public view returns (uint) {
        return _claimable;
    }

    function claim() public returns (uint){
        gtr.mint(msg.sender, _claimable);
        return _claimable;
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

contract MockPool is ERC20 {
    
    MockWETH public asset;

    constructor() {
        asset = new MockWETH();
    }

    function deposit(uint amount) external returns (uint) {
        asset.transferFrom(msg.sender, address(this), amount);
        mint(msg.sender, amount);
        return amount;
    }

    function withdraw(uint amount) external returns (uint) {
        asset.transfer(msg.sender, amount);
        burnFrom(msg.sender, amount);
        return amount;
    }
}

contract VaultTest is Test {

    MockPool public pool;
    ERC20 public gtr;
    Vault public vault;
    MockFactory public factory;

    receive() external payable {}

    function setUp() public {
        pool = new MockPool();
        gtr = new ERC20();
        factory = new MockFactory(gtr);
        vm.prank(address(factory));
        vault = new Vault(
            address(pool),
            true,
            address(gtr)
        );
    }

    function test_constructor() public {
        assertEq(address(vault.pool()), address(pool));
        assertEq(address(vault.asset()), address(pool.asset()));
        assertEq(address(vault.gtr()), address(gtr));
        assertEq(address(vault.factory()), address(factory));
        assertEq(vault.isWETH(), true);
        assertEq(pool.asset().allowance(address(vault), address(pool)), type(uint256).max);
    }

    function test_depositShares() public {
        uint amount = 100;
        pool.asset().mint(address(this), amount);
        pool.asset().approve(address(pool), type(uint256).max);
        pool.deposit(amount);
        pool.approve(address(vault), type(uint256).max);
        vault.depositShares(amount);
        assertEq(vault.balanceOf(address(this)), amount);
        assertEq(pool.balanceOf(address(vault)), amount);
        assertEq(vault.totalSupply(), amount);

        // withdraw
        vault.withdrawShares(amount);
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(pool.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function test_withdrawSharesWithApprove() public {
        uint amount = 100;
        pool.asset().mint(address(this), amount);
        pool.asset().approve(address(pool), type(uint256).max);
        pool.deposit(amount);
        pool.approve(address(vault), type(uint256).max);
        vault.depositShares(amount);
        assertEq(vault.balanceOf(address(this)), amount);
        assertEq(pool.balanceOf(address(vault)), amount);
        assertEq(vault.totalSupply(), amount);

        // withdraw with approve
        vault.approve(address(1), amount);
        vm.prank(address(1));
        vault.withdrawShares(amount, address(1), address(this));
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(pool.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.allowance(address(this), address(1)), 0);
    }

    function test_depositSharesRecipient() public {
        uint amount = 100;
        pool.asset().mint(address(this), amount);
        pool.asset().approve(address(pool), type(uint256).max);
        pool.deposit(amount);
        pool.approve(address(vault), type(uint256).max);
        vault.depositShares(amount, address(1));
        assertEq(vault.balanceOf(address(1)), amount);
        assertEq(pool.balanceOf(address(vault)), amount);
        assertEq(vault.totalSupply(), amount);

        // withdraw
        vm.prank(address(1));
        vault.withdrawShares(amount, address(1), address(1));
        assertEq(vault.balanceOf(address(1)), 0);
        assertEq(pool.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function test_depositAsset() public {
        uint amount = 100;
        pool.asset().mint(address(this), amount);
        pool.asset().approve(address(vault), type(uint256).max);
        vault.depositAsset(amount);
        assertEq(vault.balanceOf(address(this)), amount);
        assertEq(pool.balanceOf(address(vault)), amount);
        assertEq(vault.totalSupply(), amount);

        // withdraw
        vault.withdrawAsset(amount);
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(pool.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function test_withdrawAssetWithApprove() public {
        uint amount = 100;
        pool.asset().mint(address(this), amount);
        pool.asset().approve(address(vault), type(uint256).max);
        vault.depositAsset(amount);
        assertEq(vault.balanceOf(address(this)), amount);
        assertEq(pool.balanceOf(address(vault)), amount);
        assertEq(vault.totalSupply(), amount);

        // withdraw with approve
        vault.approve(address(1), amount);
        vm.prank(address(1));
        vault.withdrawAsset(amount, address(1), address(this));
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(pool.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.allowance(address(this), address(1)), 0);
    }

    function test_depositAssetRecipient() public {
        uint amount = 100;
        pool.asset().mint(address(this), amount);
        pool.asset().approve(address(vault), type(uint256).max);
        vault.depositAsset(amount, address(1));
        assertEq(vault.balanceOf(address(1)), amount);
        assertEq(pool.balanceOf(address(vault)), amount);
        assertEq(vault.totalSupply(), amount);

        // withdraw
        vm.prank(address(1));
        vault.withdrawAsset(amount, address(1), address(1));
        assertEq(vault.balanceOf(address(1)), 0);
        assertEq(pool.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function test_depositETH() public {
        uint amount = 100;
        vault.depositETH{value: amount}();
        assertEq(vault.balanceOf(address(this)), amount);
        assertEq(pool.balanceOf(address(vault)), amount);
        assertEq(vault.totalSupply(), amount);

        uint prevBalance = address(this).balance;
        // withdraw ETH
        vault.withdrawETH(amount);
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(pool.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(address(this).balance, prevBalance + amount);
    }

    function test_withdrawETHWithApprove() public {
        uint amount = 100;
        vault.depositETH{value: amount}();
        assertEq(vault.balanceOf(address(this)), amount);
        assertEq(pool.balanceOf(address(vault)), amount);
        assertEq(vault.totalSupply(), amount);

        // withdraw with approve
        vault.approve(address(1), amount);
        vm.prank(address(1));
        vault.withdrawETH(amount, payable(address(2)), address(this));
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(pool.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(address(2).balance, amount);
        assertEq(vault.allowance(address(this), address(1)), 0);
    }

    function test_depositETHRecipient() public {
        uint amount = 100;
        vault.depositETH{value: amount}(address(1));
        assertEq(vault.balanceOf(address(1)), amount);
        assertEq(pool.balanceOf(address(vault)), amount);
        assertEq(vault.totalSupply(), amount);

        // withdraw
        vm.prank(address(1));
        vault.withdrawETH(amount, payable(address(2)), address(1));
        assertEq(vault.balanceOf(address(1)), 0);
        assertEq(pool.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(address(2).balance, amount);
    }

    function test_approve() public {
        vault.approve(address(1), 100);
        assertEq(vault.allowance(address(this), address(1)), 100);
    }

    function test_claimable() public {
        uint amount = 1e18;
        pool.asset().mint(address(this), amount);
        pool.asset().approve(address(vault), type(uint256).max);
        vault.depositAsset(amount);
        assertEq(vault.balanceOf(address(this)), amount);

        uint claimable = 1e18;
        factory.setClaimable(claimable);

        assertEq(vault.claimable(address(this)), claimable);

        // another equal deposit
        pool.asset().mint(address(this), amount);
        vault.depositAsset(amount, address(1));
        assertEq(vault.balanceOf(address(1)), amount);

        assertEq(vault.claimable(address(this)), claimable / 2);
        assertEq(vault.claimable(address(1)), claimable / 2);
    }

    function test_claim() public {
        uint amount = 1e18;
        pool.asset().mint(address(this), amount);
        pool.asset().approve(address(vault), type(uint256).max);
        vault.depositAsset(amount);
        assertEq(vault.balanceOf(address(this)), amount);

        uint claimable = 1e18;
        factory.setClaimable(claimable);
        skip(1);
        vault.claim();
        assertEq(gtr.balanceOf(address(this)), claimable);
    }

}