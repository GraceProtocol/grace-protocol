// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}

interface IPool {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function deposit(uint256 assets, address recipient) external returns (uint256 shares);
    function mint(uint256 shares, address recipient) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function borrow(uint256 amount, address owner, address recipient) external;
    function repay(address to, uint amount) external;
    function asset() external view returns (address);
    function convertToShares(uint256 assets) external view returns (uint256);
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function permitBorrow(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
}

interface ICollateral {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function deposit(uint256 assets, address recipient) external returns (uint256 shares);
    function mint(uint256 shares, address recipient) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function asset() external view returns (address);
    function convertToShares(uint256 assets) external view returns (uint256);
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}

interface IBond {
    function asset() external view returns (address);
    function deposit(uint amount, address recipient) external;
    function withdraw(uint amount) external;
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}

contract Helper {

    using SafeERC20 for IERC20;

    IWETH public immutable weth;
    
    constructor(address _weth) {
        weth = IWETH(_weth);
    }

    modifier onlySameAsset(address pool, address bond) {
        require(IBond(bond).asset() == pool, "PoolBondHelper: onlySameAsset");
        _;
    }

    modifier onlyWethPools(address pool) {
        require(IPool(pool).asset() == address(weth), "onlyWethPools");
        _;
    }

    modifier onlyWethCollaterals(address collateral) {
        require(ICollateral(collateral).asset() == address(weth), "onlyWethCollaterals");
        _;
    }

    /***
     *  Pool helper functions
     */

    function poolDepositEth(address pool, address recipient) external payable onlyWethPools(pool) {
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);
        IPool(pool).deposit(msg.value, recipient);
    }

    function poolMintEth(address pool, uint256 shares, address recipient) external payable onlyWethPools(pool) {
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);
        require(shares >= IPool(pool).mint(shares, recipient), "received less shares than expected");
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(msg.sender).transfer(wethBalance);
        }
    }

    function poolWithdrawEth(address pool, uint256 assets, address receiver) external onlyWethPools(pool) {
        IPool(pool).withdraw(assets, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function poolWithdrawEthWithPermit(address pool, uint256 assets, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyWethPools(pool) {
        uint shares = IPool(pool).convertToShares(assets);
        IPool(pool).permit(msg.sender, address(this), shares, deadline, v, r, s);
        IPool(pool).withdraw(assets, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function poolRedeemEth(address pool, uint256 shares, address receiver) external onlyWethPools(pool) {
        IPool(pool).redeem(shares, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function poolRedeemEthWithPermit(address pool, uint256 shares, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyWethPools(pool) {
        IPool(pool).permit(msg.sender, address(this), shares, deadline, v, r, s);
        IPool(pool).redeem(shares, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function poolBorrowEth(address pool, uint256 amount, address recipient) external onlyWethPools(pool) {
        IPool(pool).borrow(amount, msg.sender, address(this));
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(recipient).transfer(wethBalance);
        }
    }

    function poolBorrowEthWithPermit(address pool, uint256 amount, address recipient, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyWethPools(pool) {
        IPool(pool).permitBorrow(msg.sender, address(this), amount, deadline, v, r, s);
        IPool(pool).borrow(amount, msg.sender, address(this));
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(recipient).transfer(wethBalance);
        }
    }

    function poolRepayEth(address pool, address recipient) external payable onlyWethPools(pool) {
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);
        IPool(pool).repay(recipient, msg.value);
    }

    /***
     *  Collateral helper functions
     */

    function collateralDepositEth(address collateral, address recipient) external payable onlyWethCollaterals(collateral) {
        weth.deposit{value: msg.value}();
        weth.approve(collateral, msg.value);
        ICollateral(collateral).deposit(msg.value, recipient);
    }

    function collateralMintEth(address collateral, uint256 shares, address recipient) external payable onlyWethCollaterals(collateral) {
        weth.deposit{value: msg.value}();
        weth.approve(collateral, msg.value);
        require(shares >= ICollateral(collateral).mint(shares, recipient), "received less shares than expected");
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(msg.sender).transfer(wethBalance);
        }
    }

    function collateralWithdrawEth(address collateral, uint256 assets, address receiver) external onlyWethCollaterals(collateral) {
        ICollateral(collateral).withdraw(assets, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function collateralWithdrawEthWithPermit(address collateral, uint256 assets, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyWethCollaterals(collateral) {
        uint shares = ICollateral(collateral).convertToShares(assets);
        ICollateral(collateral).permit(msg.sender, address(this), shares, deadline, v, r, s);
        ICollateral(collateral).withdraw(assets, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function collateralRedeemEth(address collateral, uint256 shares, address receiver) external onlyWethCollaterals(collateral) {
        ICollateral(collateral).redeem(shares, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function collateralRedeemEthWithPermit(address collateral, uint256 shares, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyWethCollaterals(collateral) {
        ICollateral(collateral).permit(msg.sender, address(this), shares, deadline, v, r, s);
        ICollateral(collateral).redeem(shares, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    /***
     *  Pool+bond helper functions
     */    

    function depositAndBond(address pool, address bond, uint assets) external onlySameAsset(pool, bond){
        IERC20 asset = IERC20(IPool(pool).asset());
        asset.safeTransferFrom(msg.sender, address(this), assets);
        asset.forceApprove(pool, assets);
        uint shares = IPool(pool).deposit(assets, address(this));
        IERC20(pool).approve(bond, shares);
        IBond(bond).deposit(shares, msg.sender);
    }

    function depositAndBondEth(address pool, address bond) external payable onlyWethPools(pool) onlySameAsset(pool, bond){
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);
        uint shares = IPool(pool).deposit(msg.value, address(this));
        IERC20(pool).approve(bond, shares);
        IBond(bond).deposit(shares, msg.sender);
    }

    function mintAndBond(address pool, address bond, uint shares) external onlySameAsset(pool, bond){
        IERC20 asset = IERC20(IPool(pool).asset());
        uint assets = IPool(pool).previewMint(shares);
        asset.safeTransferFrom(msg.sender, address(this), assets);
        asset.forceApprove(pool, assets);
        IPool(pool).mint(shares, address(this));
        IERC20(pool).approve(bond, shares);
        IBond(bond).deposit(shares, msg.sender);
    }

    function mintAndBondEth(address pool, address bond, uint shares) external payable onlyWethPools(pool) onlySameAsset(pool, bond){
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);
        IPool(pool).mint(shares, address(this));
        IERC20(pool).approve(bond, shares);
        IBond(bond).deposit(shares, msg.sender);
        uint wethBal = weth.balanceOf(address(this));
        if (wethBal > 0) {
            weth.withdraw(wethBal);
            payable(msg.sender).transfer(wethBal);
        }
    }
    
    function unbondAndWithdraw(address bond, uint assets) external {
        IPool pool = IPool(IBond(bond).asset());
        uint shares = pool.previewWithdraw(assets);
        IERC20(bond).transferFrom(msg.sender, address(this), shares);
        IBond(bond).withdraw(shares);
        pool.withdraw(assets, msg.sender, address(this));
    }

    function unbondAndWithdrawEth(address bond, uint assets) external onlyWethPools(IBond(bond).asset()) {
        IPool pool = IPool(IBond(bond).asset());
        uint shares = pool.previewWithdraw(assets);
        IERC20(bond).transferFrom(msg.sender, address(this), shares);
        IBond(bond).withdraw(shares);
        pool.withdraw(assets, address(this), address(this));
        uint wethBal = weth.balanceOf(address(this));
        if (wethBal > 0) {
            weth.withdraw(wethBal);
            payable(msg.sender).transfer(wethBal);
        }
    }

    function unbondAndWithdrawWithPermit(address bond, uint assets, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        IPool pool = IPool(IBond(bond).asset());
        uint shares = pool.previewWithdraw(assets);
        IBond(bond).permit(msg.sender, address(this), shares, deadline, v, r, s);
        IERC20(bond).transferFrom(msg.sender, address(this), shares);
        IBond(bond).withdraw(shares);
        pool.withdraw(assets, msg.sender, address(this));
    }

    function unbondAndRedeem(address bond, uint shares) external {
        IERC20(bond).transferFrom(msg.sender, address(this), shares);
        IBond(bond).withdraw(shares);
        IPool pool = IPool(IBond(bond).asset());
        pool.redeem(shares, msg.sender, address(this));
    }

    function unbondAndRedeemEth(address bond, uint shares) external onlyWethPools(IBond(bond).asset()) {
        IERC20(bond).transferFrom(msg.sender, address(this), shares);
        IBond(bond).withdraw(shares);
        IPool pool = IPool(IBond(bond).asset());
        pool.redeem(shares, address(this), address(this));
        uint wethBal = weth.balanceOf(address(this));
        if (wethBal > 0) {
            weth.withdraw(wethBal);
            payable(msg.sender).transfer(wethBal);
        }
    }

    function unbondAndRedeemWithPermit(address bond, uint shares, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        IBond(bond).permit(msg.sender, address(this), shares, deadline, v, r, s);
        IERC20(bond).transferFrom(msg.sender, address(this), shares);
        IBond(bond).withdraw(shares);
        IPool pool = IPool(IBond(bond).asset());
        pool.redeem(shares, msg.sender, address(this));
    }

}