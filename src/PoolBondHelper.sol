// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IPool {
    function asset() external view returns (address);
    function deposit(uint256 assets, address recipient) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function mint(uint256 shares, address recipient) external returns (uint256 assets);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
}

interface IBond {
    function asset() external view returns (address);
    function deposit(uint amount, address recipient) external;
    function preorder(uint amount, address recipient) external;
    function cancelPreorder(uint amount) external;
    function withdraw(uint amount) external;
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract PoolBondHelper {

    modifier onlySameAsset(address pool, address bond) {
        require(IBond(bond).asset() == pool, "PoolBondHelper: onlySameAsset");
        _;
    }

    function depositAndBond(address pool, address bond, uint assets) external onlySameAsset(pool, bond){
        IERC20 asset = IERC20(IPool(pool).asset());
        asset.transferFrom(msg.sender, address(this), assets);
        asset.approve(pool, assets);
        uint shares = IPool(pool).deposit(assets, address(this));
        IERC20(pool).approve(bond, shares);
        IBond(bond).deposit(shares, msg.sender);
    }

    function mintAndBond(address pool, address bond, uint shares) external onlySameAsset(pool, bond){
        IERC20 asset = IERC20(IPool(pool).asset());
        uint assets = IPool(pool).previewMint(shares);
        asset.transferFrom(msg.sender, address(this), assets);
        asset.approve(pool, assets);
        IPool(pool).mint(shares, address(this));
        IERC20(pool).approve(bond, shares);
        IBond(bond).deposit(shares, msg.sender);
    }

    function depositAndPreorder(address pool, address bond, uint assets) external onlySameAsset(pool, bond){
        IERC20 asset = IERC20(IPool(pool).asset());
        asset.transferFrom(msg.sender, address(this), assets);
        asset.approve(pool, assets);
        uint shares = IPool(pool).deposit(assets, address(this));
        IERC20(pool).approve(bond, shares);
        IBond(bond).preorder(shares, msg.sender);
    }

    function mintAndPreorder(address pool, address bond, uint shares) external onlySameAsset(pool, bond){
        IERC20 asset = IERC20(IPool(pool).asset());
        uint assets = IPool(pool).previewMint(shares);
        asset.transferFrom(msg.sender, address(this), assets);
        asset.approve(pool, assets);
        IPool(pool).mint(shares, address(this));
        IERC20(pool).approve(bond, shares);
        IBond(bond).preorder(shares, msg.sender);
    }
    
    function unbondAndWithdraw(address bond, uint assets) external {
        IPool pool = IPool(IBond(bond).asset());
        uint shares = pool.previewWithdraw(assets);
        IERC20(bond).transferFrom(msg.sender, address(this), shares);
        IBond(bond).withdraw(shares);
        pool.withdraw(assets, msg.sender, address(this));
    }

    function cancelPreorderAndWithdraw(address bond, uint assets) external {
        IPool pool = IPool(IBond(bond).asset());
        uint shares = pool.previewWithdraw(assets);
        IERC20(bond).transferFrom(msg.sender, address(this), shares);
        IBond(bond).cancelPreorder(shares);
        pool.withdraw(assets, msg.sender, address(this));
    }

    function unbondAndRedeem(address bond, uint shares) external {
        IERC20(bond).transferFrom(msg.sender, address(this), shares);
        IBond(bond).withdraw(shares);
        IPool pool = IPool(IBond(bond).asset());
        pool.redeem(shares, msg.sender, address(this));
    }

    function cancelPreorderAndRedeem(address bond, uint shares) external {
        IERC20(bond).transferFrom(msg.sender, address(this), shares);
        IBond(bond).cancelPreorder(shares);
        IPool pool = IPool(IBond(bond).asset());
        pool.redeem(shares, msg.sender, address(this));
    }

}