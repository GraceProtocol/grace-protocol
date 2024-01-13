// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ICollateralCore {
    function onCollateralDeposit(address recipient, uint256 amount) external returns (bool);
    function onCollateralWithdraw(address caller, uint256 amount) external returns (bool);
    function getCollateralFeeBps(address collateral, uint lastFee, uint lastAccrued) external view returns (uint256);
    function feeDestination() external view returns (address);
    function globalLock(address caller) external;
    function globalUnlock() external;
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract Collateral {

    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    bool public isWETH;
    ICollateralCore public immutable core;
    uint public totalSupply;
    uint public lastAccrued;
    uint public lastBalance;
    uint public lastFeeBps;
    uint constant MINIMUM_BALANCE = 10**3;
    uint256 internal constant MAX_UINT256 = 2**256 - 1;
    bytes32 public immutable DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    mapping(address => uint) public nonces;

    constructor(IERC20 _asset, bool _isWETH, address _core) {
        asset = _asset;
        isWETH = _isWETH;
        core = ICollateralCore(_core);
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes("Grace Collateral")),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    modifier lock {
        core.globalLock(msg.sender);
        _;
        core.globalUnlock();
    }

    modifier onlyWETH {
        require(isWETH, "onlyWETH");
        _;
    }

    receive() external payable {}

    function accrueFee() internal returns (uint _lastAccrued) {
        _lastAccrued = lastAccrued;
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return _lastAccrued;
        if(lastFeeBps == 0) {
            lastAccrued = block.timestamp;
            return _lastAccrued;
        }
        uint balance = lastBalance;
        uint256 fee = balance * lastFeeBps * timeElapsed / 10000 / 365 days;
        if(fee > balance) fee = balance;
        if(balance - fee < MINIMUM_BALANCE) fee = balance > MINIMUM_BALANCE ? balance - MINIMUM_BALANCE : 0;
        if(fee == 0) return _lastAccrued;
        lastAccrued = block.timestamp;
        asset.safeTransfer(core.feeDestination(), fee);
    }

    function updateFee(uint _lastAccrued) internal {
        lastFeeBps = core.getCollateralFeeBps(address(this), lastFeeBps, _lastAccrued);
    }

    function totalAssets() public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return lastBalance;
        uint feeBps = lastFeeBps;
        if(feeBps == 0) return lastBalance;
        uint balance = lastBalance;
        uint256 fee = balance * feeBps * timeElapsed / 10000 / 365 days;
        if(fee > balance) fee = balance;
        if(balance - fee < MINIMUM_BALANCE) fee = balance > MINIMUM_BALANCE ? balance - MINIMUM_BALANCE : 0;
        return balance - fee;
    }

    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))) {
                revert(0, 0)
            }

            // If x * y modulo the denominator is strictly greater than 0,
            // 1 is added to round up the division of x * y by the denominator.
            z := add(gt(mod(mul(x, y), denominator), 0), div(mul(x, y), denominator))
        }
    }

    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))) {
                revert(0, 0)
            }

            // Divide x * y by the denominator.
            z := div(mul(x, y), denominator)
        }
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : mulDivDown(assets, totalSupply, totalAssets());
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : mulDivDown(shares, totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : mulDivUp(assets, supply, totalAssets());
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    function deposit(uint256 assets, address recipient) public lock returns (uint256 shares) {
        uint _lastAccrued = accrueFee();
        require(core.onCollateralDeposit(recipient, assets), "beforeCollateralDeposit");
        require((shares = previewDeposit(assets)) != 0, "zeroShares");
        balanceOf[recipient] += shares;
        totalSupply += shares;
        asset.safeTransferFrom(msg.sender, address(this), assets);
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Deposit(msg.sender, recipient, assets, shares);
        updateFee(_lastAccrued);
    }

    function deposit(uint256 assets) public returns (uint256 shares) {
        return deposit(assets, msg.sender);
    }

    function depositETH(address recipient) public payable onlyWETH lock returns (uint256 shares) {
        uint _lastAccrued = accrueFee();
        require(core.onCollateralDeposit(recipient, msg.value), "beforeCollateralDeposit");
        require((shares = previewDeposit(msg.value)) != 0, "zeroShares");
        balanceOf[recipient] += shares;
        totalSupply += shares;
        IWETH(address(asset)).deposit{value: msg.value}();
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Deposit(msg.sender, recipient, msg.value, shares);
        updateFee(_lastAccrued);
    }

    function depositETH() public payable returns (uint256 shares) {
        return depositETH(msg.sender);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : mulDivUp(shares, totalAssets(), supply);
    }

    function mint(uint256 shares, address recipient) public lock returns (uint256 assets) {
        uint _lastAccrued = accrueFee();
        assets = previewMint(shares);
        require(core.onCollateralDeposit(recipient, assets), "beforeCollateralDeposit");
        balanceOf[recipient] += shares;
        totalSupply += shares;
        asset.safeTransferFrom(msg.sender, address(this), assets);
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Deposit(msg.sender, recipient, assets, shares);
        updateFee(_lastAccrued);
    }

    function mint(uint256 shares) public returns (uint256 assets) {
        return mint(shares, msg.sender);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public lock returns (uint256 shares) {
        uint _lastAccrued = accrueFee();
        require(core.onCollateralWithdraw(owner, assets), "beforeCollateralWithdraw");
        shares = previewWithdraw(assets);
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        totalSupply -= shares;
        balanceOf[owner] -= shares;
        asset.safeTransfer(receiver, assets);
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        updateFee(_lastAccrued);
    }

    function withdraw(uint256 assets) public returns (uint256 shares) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    function withdrawETH(
        uint256 assets,
        address payable receiver,
        address owner
    ) public onlyWETH lock returns (uint256 shares) {
        uint _lastAccrued = accrueFee();
        require(core.onCollateralWithdraw(owner, assets), "beforeCollateralWithdraw");
        shares = previewWithdraw(assets);
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        totalSupply -= shares;
        balanceOf[owner] -= shares;
        IWETH(address(asset)).withdraw(assets);
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        updateFee(_lastAccrued);
        receiver.transfer(assets);
    }

    function withdrawETH(uint256 assets) public returns (uint256 shares) {
        return withdrawETH(assets, payable(msg.sender), msg.sender);
    }

    function redeem(uint256 shares, address receiver, address owner) public lock returns (uint256 assets) {
        uint _lastAccrued = accrueFee();
        assets = previewRedeem(shares);
        require(core.onCollateralWithdraw(owner, assets), "beforeCollateralWithdraw");
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        totalSupply -= shares;
        balanceOf[owner] -= shares;
        asset.safeTransfer(receiver, assets);
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        updateFee(_lastAccrued);
    }

    function redeem(uint256 shares) public returns (uint256 assets) {
        return redeem(shares, msg.sender, msg.sender);
    }

    function redeemETH(uint256 shares, address payable receiver, address owner) public onlyWETH lock returns (uint256 assets) {
        uint _lastAccrued = accrueFee();
        assets = previewRedeem(shares);
        require(core.onCollateralWithdraw(owner, assets), "beforeCollateralWithdraw");
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        totalSupply -= shares;
        balanceOf[owner] -= shares;
        IWETH(address(asset)).withdraw(assets);
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        updateFee(_lastAccrued);
        receiver.transfer(assets);
    }

    function redeemETH(uint256 shares) public returns (uint256 assets) {
        return redeemETH(shares, payable(msg.sender), msg.sender);
    }

    function approve(address spender, uint256 shares) public returns (bool) {
        allowance[msg.sender][spender] = shares;
        emit Approval(msg.sender, spender, shares);
        return true;
    }

    function permit(address owner, address spender, uint256 shares, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
        require(deadline >= block.timestamp, "Collateral: EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, shares, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "Collateral: INVALID_SIGNATURE");
        allowance[owner][spender] = shares;
        emit Approval(owner, spender, shares);
    }

    function getCollateralOf(address account) public view returns (uint256) {
        return convertToAssets(balanceOf[account]);
    }

    function seize(address account, uint256 assets, address to) public lock {
        uint _lastAccrued = accrueFee();
        require(msg.sender == address(core), "onlyCore");
        uint shares = convertToShares(assets);
        totalSupply -= shares;
        balanceOf[account] -= shares;
        asset.safeTransfer(to, assets);
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Withdraw(msg.sender, to, account, shares, assets);
        updateFee(_lastAccrued);
    }

    function pull(address _stuckToken, address dst, uint amount) external {
        require(msg.sender == address(core), "onlyCore");
        require(_stuckToken != address(asset), "cannotPullUnderlying");
        IERC20(_stuckToken).safeTransfer(dst, amount);
    }

    function invalidateNonce() external {
        nonces[msg.sender]++;
    }    

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    
}
