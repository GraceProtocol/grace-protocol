// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/Collateral.sol";
import "./mocks/ERC20.sol";
import "./mocks/MockCore.sol";

contract MockWETH is ERC20 {
    function deposit() external payable {
        mint(msg.sender, msg.value);
    }

    function withdraw(uint amount) external {
        burnFrom(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
    
}

contract CollateralTest is Test, MockCore {

    Collateral public collateral;
    MockWETH public asset;

    function setUp() public {
        asset = new MockWETH();
        collateral = new Collateral(
            IERC20(address(asset)),
            true,
            address(this)
        );
    }

    receive() external payable {}

    function test_constructor() public {
        assertEq(address(collateral.asset()), address(asset));
        assertEq(address(collateral.core()), address(this));
    }

    function test_deposit() public {
        asset.deposit{value: 1000}();
        asset.approve(address(collateral), 1000);
        collateral.deposit(1000);
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);   
        assertEq(collateral.getCollateralOf(address(this)), 1000);  
    }

    function test_depositRecipient() public {
        asset.deposit{value: 1000}();
        asset.approve(address(collateral), 1000);
        collateral.deposit(1000, address(1));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(1)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);   
        assertEq(collateral.getCollateralOf(address(1)), 1000);  
    }

    function test_depositETH() public {
        collateral.depositETH{value: 1000}();
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);   
        assertEq(collateral.getCollateralOf(address(this)), 1000);  
    }

    function test_depositETHRecipient() public {
        collateral.depositETH{value: 1000}(address(1));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(1)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);   
        assertEq(collateral.getCollateralOf(address(1)), 1000);  
    }

    function test_mint() public {
        asset.deposit{value: 1000}();
        asset.approve(address(collateral), 1000);
        collateral.mint(1000);
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
    }

    function test_mintRecipient() public {
        asset.deposit{value: 1000}();
        asset.approve(address(collateral), 1000);
        collateral.mint(1000, address(1));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(1)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(1)), 1000);
    }

    function test_withdraw() public {
        asset.deposit{value: 2000}();
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        collateral.withdraw(2000);
        collateral.withdraw(1000);
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
    }

    function test_withdrawOnBehalfToRecipient() public {
        asset.deposit{value: 2000}();
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(this));
        collateral.approve(address(1), 1000);
        vm.startPrank(address(1));
        collateral.withdraw(1000, address(2), address(this));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
        assertEq(asset.balanceOf(address(2)), 1000);
    }

    function test_withdrawETH() public {
        asset.deposit{value: 2000}();
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        collateral.withdrawETH(2000);
        uint balBefore = address(this).balance;
        collateral.withdrawETH(1000);
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
        assertEq(address(this).balance, balBefore + 1000);
    }

    function test_withdrawETHOnBehalfToRecipient() public {
        asset.deposit{value: 2000}();
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(this));
        collateral.approve(address(1), 2000);
        vm.startPrank(address(1));
        vm.expectRevert("minimumBalance");
        collateral.withdrawETH(2000, payable(address(2)), address(this));
        collateral.withdrawETH(1000, payable(address(2)), address(this));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
        assertEq(address(2).balance, 1000);
    }

    function test_redeem() public {
        asset.deposit{value: 2000}();
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        collateral.redeem(2000);
        collateral.redeem(1000);
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
    }

    function test_redeemOnBehalfToRecipient() public {
        asset.deposit{value: 2000}();
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(this));
        collateral.approve(address(1), 2000);
        vm.startPrank(address(1));
        vm.expectRevert("minimumBalance");
        collateral.redeem(2000, address(2), address(this));
        collateral.redeem(1000, address(2), address(this));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
        assertEq(asset.balanceOf(address(2)), 1000);
    }

    function test_redeemETH() public {
        asset.deposit{value: 2000}();
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        collateral.redeemETH(2000);
        uint balBefore = address(this).balance;
        collateral.redeemETH(1000);
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
        assertEq(address(this).balance, balBefore + 1000);
    }

    function test_redeemETHOnBehalfToRecipient() public {
        asset.deposit{value: 2000}();
        asset.approve(address(collateral), 2000);
        collateral.deposit(2000, address(this));
        collateral.approve(address(1), 2000);
        vm.startPrank(address(1));
        vm.expectRevert("minimumBalance");
        collateral.redeemETH(2000, payable(address(2)), address(this));
        collateral.redeemETH(1000, payable(address(2)), address(this));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(collateral.balanceOf(address(this)), 1000);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(this)), 1000);
        assertEq(address(2).balance, 1000);
    }

    function test_approve() public {
        asset.deposit{value: 1000}();
        asset.approve(address(collateral), 1000);
        collateral.deposit(1000, address(this));
        collateral.approve(address(1), 1000);
        assertEq(collateral.allowance(address(this), address(1)), 1000);
    }

    function test_seize() public {
        asset.deposit{value: 2000}();
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

    function test_seizeAll() public {
        // add 1000 from address(1) to avoid minimumBalance
        asset.deposit{value: 1000}();
        asset.transfer(address(1), 1000);
        vm.startPrank(address(1));
        asset.approve(address(collateral), 1000);
        collateral.deposit(1000, address(1));
        vm.stopPrank();


        asset.deposit{value: 1000}();
        asset.approve(address(collateral), 1000);
        collateral.deposit(1000);
        collateral.seize(address(this), type(uint).max, address(this));
        assertEq(asset.balanceOf(address(collateral)), 1000);
        assertEq(asset.balanceOf(address(this)), 1000);
        assertEq(collateral.balanceOf(address(1)), 1000);
        assertEq(collateral.balanceOf(address(this)), 0);
        assertEq(collateral.totalSupply(), 1000);
        assertEq(collateral.lastBalance(), 1000);
        assertEq(collateral.getCollateralOf(address(1)), 1000);  
    }

    function test_pull() public {
        asset.deposit{value: 1000}();
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
        asset.deposit{value: 10000}();
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

    function test_permit() public {
        uint signerPrivateKey = 0xa11ce;
        address OWNER = vm.addr(signerPrivateKey);
        address SPENDER = address(1);
        uint VALUE = 1;
        uint NONCE = 0;
        uint DEADLINE = type(uint256).max;
        bytes32 PERMIT_TYPEHASH = collateral.PERMIT_TYPEHASH();
        bytes32 DOMAIN_SEPARATOR = collateral.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked(
            '\x19\x01',
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                PERMIT_TYPEHASH,
                OWNER,
                SPENDER,
                VALUE,
                NONCE,
                DEADLINE
            ))
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        collateral.permit(OWNER, SPENDER, VALUE, DEADLINE, v, r, s);
        assertEq(collateral.allowance(OWNER, SPENDER), VALUE);
        assertEq(collateral.nonces(OWNER), 1);
    }

}