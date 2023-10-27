// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function approve(address guy, uint wad) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
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

contract EthHelper {

    IWETH public immutable weth;
    
    constructor(IWETH _weth) {
        weth = _weth;
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

    function poolDeposit(address pool, address recipient) external payable onlyWethPools(pool) {
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);
        IPool(pool).deposit(msg.value, recipient);
    }

    function poolMint(address pool, uint256 shares, address recipient) external payable onlyWethPools(pool) {
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);
        require(shares >= IPool(pool).mint(shares, recipient), "received less shares than expected");
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(msg.sender).transfer(wethBalance);
        }
    }

    function poolWithdraw(address pool, uint256 assets, address receiver) external onlyWethPools(pool) {
        IPool(pool).withdraw(assets, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function poolWithdrawWithPermit(address pool, uint256 assets, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyWethPools(pool) {
        uint shares = IPool(pool).convertToShares(assets);
        IPool(pool).permit(msg.sender, address(this), shares, deadline, v, r, s);
        IPool(pool).withdraw(assets, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function poolRedeem(address pool, uint256 shares, address receiver) external onlyWethPools(pool) {
        IPool(pool).redeem(shares, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function poolRedeemWithPermit(address pool, uint256 shares, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyWethPools(pool) {
        IPool(pool).permit(msg.sender, address(this), shares, deadline, v, r, s);
        IPool(pool).redeem(shares, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function poolBorrow(address pool, uint256 amount, address recipient) external onlyWethPools(pool) {
        IPool(pool).borrow(amount, msg.sender, address(this));
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(recipient).transfer(wethBalance);
        }
    }

    function poolBorrowWithPermit(address pool, uint256 amount, address recipient, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyWethPools(pool) {
        IPool(pool).permitBorrow(msg.sender, address(this), amount, deadline, v, r, s);
        IPool(pool).borrow(amount, msg.sender, address(this));
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(recipient).transfer(wethBalance);
        }
    }

    function poolRepay(address pool, address recipient) external payable onlyWethPools(pool) {
        weth.deposit{value: msg.value}();
        weth.approve(pool, msg.value);
        IPool(pool).repay(recipient, msg.value);
    }

    /***
     *  Collateral helper functions
     */

    function collateralDeposit(address collateral, address recipient) external payable onlyWethCollaterals(collateral) {
        weth.deposit{value: msg.value}();
        weth.approve(collateral, msg.value);
        ICollateral(collateral).deposit(msg.value, recipient);
    }

    function collateralMint(address collateral, uint256 shares, address recipient) external payable onlyWethCollaterals(collateral) {
        weth.deposit{value: msg.value}();
        weth.approve(collateral, msg.value);
        require(shares >= ICollateral(collateral).mint(shares, recipient), "received less shares than expected");
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(msg.sender).transfer(wethBalance);
        }
    }

    function collateralWithdraw(address collateral, uint256 assets, address receiver) external onlyWethCollaterals(collateral) {
        ICollateral(collateral).withdraw(assets, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function collateralWithdrawWithPermit(address collateral, uint256 assets, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyWethCollaterals(collateral) {
        uint shares = ICollateral(collateral).convertToShares(assets);
        ICollateral(collateral).permit(msg.sender, address(this), shares, deadline, v, r, s);
        ICollateral(collateral).withdraw(assets, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function collateralRedeem(address collateral, uint256 shares, address receiver) external onlyWethCollaterals(collateral) {
        ICollateral(collateral).redeem(shares, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

    function collateralRedeemWithPermit(address collateral, uint256 shares, address receiver, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyWethCollaterals(collateral) {
        ICollateral(collateral).permit(msg.sender, address(this), shares, deadline, v, r, s);
        ICollateral(collateral).redeem(shares, address(this), msg.sender);
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            payable(receiver).transfer(wethBalance);
        }
    }

}