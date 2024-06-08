// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "../src/Pool.sol";
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

contract PoolTest is Test, MockCore {
    
    Pool public pool;
    MockWETH public asset;

    function setUp() public {
        asset = new MockWETH();
        pool = new Pool(
            "Pool",
            "POOL",
            IERC20(address(asset)),
            true,
            address(this)
        );
    }

    receive() external payable {}

    function test_constructor() public {
        assertEq(pool.name(), "Pool");
        assertEq(pool.symbol(), "POOL");
        assertEq(pool.decimals(), 18);
        assertEq(address(pool.asset()), address(asset));
        assertEq(address(pool.core()), address(this));
    }

    function test_deposit() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(1000, address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(this)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);   
        assertEq(pool.getAssetsOf(address(this)), 1000);
    }

    function test_depositRecipient() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(1000, address(1));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(1)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(1)), 1000);
    }

    function test_mint() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.mint(1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(this)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 1000);
    }

    function test_mintRecipient() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.mint(1000, address(1));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(1)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(1)), 1000);
    }

    function test_withdraw() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        pool.withdraw(2000);
        pool.withdraw(1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(this)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 1000);
    }

    function test_withdrawOnBehalfToRecipient() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        pool.approve(address(1), 2000);
        vm.startPrank(address(1));
        vm.expectRevert("minimumBalance");
        pool.withdraw(2000, address(2), address(this));
        pool.withdraw(1000, address(2), address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(this)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 1000);
        assertEq(asset.balanceOf(address(2)), 1000);
    }

    function test_redeem() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        pool.redeem(2000);
        pool.redeem(1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(this)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 1000);
    }

    function test_redeemOnBehalfToRecipient() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        pool.approve(address(1), 2000);
        vm.startPrank(address(1));
        vm.expectRevert("minimumBalance");
        pool.redeem(2000, address(2), address(this));
        pool.redeem(1000, address(2), address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(this)), 1000);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 1000);
        assertEq(asset.balanceOf(address(2)), 1000);
    }

    function test_transfer() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(1000, address(this));
        pool.transfer(address(1), 1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(1)), 1000);
        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(1)), 1000);
        assertEq(pool.getAssetsOf(address(this)), 0);
    }

    function test_approve_transferFrom() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(1000, address(this));
        pool.approve(address(1), 1000);
        assertEq(pool.allowance(address(this), address(1)), 1000);
        vm.prank(address(1));
        pool.transferFrom(address(this), address(1), 1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(pool.balanceOf(address(1)), 1000);
        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(pool.totalSupply(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(1)), 1000);
        assertEq(pool.getAssetsOf(address(this)), 0);
        assertEq(pool.allowance(address(this), address(1)), 0);
    }

    function test_borrow_repay() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        pool.borrow(2000);
        pool.borrow(1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(asset.balanceOf(address(this)), 1000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.totalDebt(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 1000);
        asset.approve(address(pool), 1000);
        pool.repay(1000);
        assertEq(asset.balanceOf(address(pool)), 2000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.lastBalance(), 2000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 0);
    }

    function test_repayAll() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        pool.borrow(2000);
        pool.borrow(1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(asset.balanceOf(address(this)), 1000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.totalDebt(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 1000);
        vm.warp(block.timestamp + 365 days);

        // 2nd borrower
        asset.mint(address(1), 1000);
        vm.startPrank(address(1));
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(1000, address(1));
        pool.borrow(999); // causes precision bug
        vm.stopPrank();

        asset.mint(address(this), 1000);
        asset.approve(address(pool), 2000);
        pool.repay(type(uint256).max);
        assertEq(asset.balanceOf(address(pool)), 3001);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 4000);
        assertEq(pool.lastBalance(), 3001);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 0);
    }

    function test_borrowOnBehalf() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        pool.approveBorrow(address(1), 1000);
        vm.prank(address(1));
        pool.borrow(1000, address(0), address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(asset.balanceOf(address(1)), 1000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.totalDebt(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 1000);
    }

    function test_repayTo() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        vm.expectRevert("minimumBalance");
        pool.borrow(2000);
        pool.borrow(1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(asset.balanceOf(address(this)), 1000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.totalDebt(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 1000);
        vm.startPrank(address(1));
        asset.mint(address(1), 1000);
        asset.approve(address(pool), 1000);
        pool.repay(address(this), 1000);
        assertEq(asset.balanceOf(address(pool)), 2000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.lastBalance(), 2000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 0);
    }

    function test_borrowETH_repayETH() public {
        asset.deposit{value:2000}();
        asset.approve(address(pool), 2000);
        pool.deposit(2000);
        vm.expectRevert("minimumBalance");
        pool.borrowETH(2000);
        uint balance = address(this).balance;
        pool.borrowETH(1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(address(this).balance, balance + 1000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.totalDebt(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 1000);
        asset.approve(address(pool), 1000);
        pool.repayETH{value:1000}();
        assertEq(asset.balanceOf(address(pool)), 2000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.lastBalance(), 2000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 0);
    }

    function test_repayETHRefund() public {
        asset.deposit{value:2000}();
        asset.approve(address(pool), 2000);
        pool.deposit(2000);
        vm.expectRevert("minimumBalance");
        pool.borrowETH(2000);
        uint balance = address(this).balance;
        pool.borrowETH(1000);
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(address(this).balance, balance + 1000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.totalDebt(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 1000);
        asset.approve(address(pool), 1000);
        uint balanceBefore = address(this).balance;
        pool.repayETH{value:1001}();
        assertEq(address(this).balance, balanceBefore - 1000); // 1 wei refund
        assertEq(asset.balanceOf(address(pool)), 2000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.lastBalance(), 2000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 0);
    }

    function test_writeOff() public {
        asset.mint(address(this), 2000);
        asset.approve(address(pool), 2000);
        pool.deposit(2000, address(this));
        pool.borrow(1000, address(0), address(this));
        assertEq(asset.balanceOf(address(pool)), 1000);
        assertEq(asset.balanceOf(address(this)), 1000);
        assertEq(pool.balanceOf(address(this)), 2000);
        assertEq(pool.totalSupply(), 2000);
        assertEq(pool.totalDebt(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.getAssetsOf(address(this)), 2000);
        assertEq(pool.getDebtOf(address(this)), 1000);
        assertEq(pool.totalAssets(), 2000);
        assertEq(pool.totalDebt(), 1000);
        pool.writeOff(address(this));
        assertEq(pool.totalAssets(), 1000);
        assertEq(pool.lastBalance(), 1000);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.getAssetsOf(address(this)), 1000);
        assertEq(pool.getDebtOf(address(this)), 0);
    }

    function test_invalidateNonce() public {
        assertEq(pool.nonces(address(this)), 0);
        pool.invalidateNonce();
        assertEq(pool.nonces(address(this)), 1);
    }

    function test_accrueInterest() public {
        uint DEPOSIT = 2000;
        uint BORROW = 1000;
        uint INTEREST = 1000;
        asset.mint(address(this), DEPOSIT + INTEREST);
        asset.approve(address(pool), DEPOSIT + BORROW + INTEREST);
        pool.deposit(DEPOSIT, address(this));
        pool.borrow(BORROW, address(0), address(this));
        vm.warp(block.timestamp + 365 days);
        // mock core sets borrow rate to 100%, so we expect 1000 interest
        assertEq(pool.getDebtOf(address(this)), BORROW + INTEREST);
        assertEq(pool.getAssetsOf(address(this)), DEPOSIT);
        pool.repay(address(this), BORROW + INTEREST);
        assertEq(pool.getAssetsOf(address(1)), INTEREST);
        assertEq(pool.balanceOf(address(1)), INTEREST);
        assertEq(pool.totalSupply(), DEPOSIT + INTEREST);
        assertEq(pool.lastBorrowRate(), 10000);
        assertEq(pool.lastBalance(), DEPOSIT + INTEREST);
    }

    function test_approveBorrow () public {
        pool.approveBorrow(address(1), type(uint256).max);
        assertEq(pool.borrowAllowance(address(this), address(1)), type(uint256).max);
    }

    function test_pull() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(1000, address(this));
        vm.expectRevert("cannotPullUnderlying");
        pool.pull(address(asset), address(1), 1000);
        ERC20 stuckToken = new ERC20();
        stuckToken.mint(address(pool), 1000);
        pool.pull(address(stuckToken), address(this), 1000);
        assertEq(stuckToken.balanceOf(address(pool)), 0);
        assertEq(stuckToken.balanceOf(address(this)), 1000);
    }

    function test_claimReferralRewards() public {
        address REFERRER = address(2);
        uint LIQUIDITY = 10e18;
        uint BORROW = 1e18;
        asset.mint(address(this), LIQUIDITY);
        asset.approve(address(pool), LIQUIDITY);
        pool.deposit(LIQUIDITY, address(this));
        pool.borrow(BORROW, REFERRER, address(this));
        vm.warp(block.timestamp + 365 days);
        assertEq(pool.balanceOf(REFERRER), 0);
        vm.startPrank(REFERRER);
        pool.claimReferralRewards();
        assertEq(pool.balanceOf(REFERRER), BORROW / 10);
        pool.redeem(BORROW / 10);
        assertEq(asset.balanceOf(REFERRER), BORROW / 10);
    }

    function test_getDebtOf() public {
        uint DEPOSIT = 2000;
        uint BORROW = 1000;
        asset.mint(address(this), DEPOSIT);
        asset.approve(address(pool), DEPOSIT + BORROW);
        pool.deposit(DEPOSIT, address(this));
        pool.borrow(BORROW, address(1), address(this));
        assertEq(pool.getDebtOf(address(this)), BORROW);
        vm.warp(block.timestamp + 365 days);
        assertEq(pool.getDebtOf(address(this)), BORROW * 2);
    }

    function test_permit() public {
        uint signerPrivateKey = 0xa11ce;
        address OWNER = vm.addr(signerPrivateKey);
        address SPENDER = address(1);
        uint VALUE = 1;
        uint NONCE = 0;
        uint DEADLINE = type(uint256).max;
        bytes32 PERMIT_TYPEHASH = pool.PERMIT_TYPEHASH();
        bytes32 DOMAIN_SEPARATOR = pool.DOMAIN_SEPARATOR();
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
        pool.permit(OWNER, SPENDER, VALUE, DEADLINE, v, r, s);
        assertEq(pool.allowance(OWNER, SPENDER), VALUE);
        assertEq(pool.nonces(OWNER), 1);
    }

    function test_permitBorrow() public {
        uint signerPrivateKey = 0xa11ce;
        address OWNER = vm.addr(signerPrivateKey);
        address SPENDER = address(1);
        uint VALUE = 1;
        uint NONCE = 0;
        uint DEADLINE = type(uint256).max;
        bytes32 PERMIT_TYPEHASH = pool.PERMIT_BORROW_TYPEHASH();
        bytes32 DOMAIN_SEPARATOR = pool.DOMAIN_SEPARATOR();
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
        pool.permitBorrow(OWNER, SPENDER, VALUE, DEADLINE, v, r, s);
        assertEq(pool.borrowAllowance(OWNER, SPENDER), VALUE);
        assertEq(pool.nonces(OWNER), 1);
    }
}