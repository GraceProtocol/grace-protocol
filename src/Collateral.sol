// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface ICollateralCore {
    function onCollateralDeposit(address recipient, uint256 amount) external returns (bool);
    function onCollateralWithdraw(address caller, uint256 amount) external returns (bool);
    function onCollateralReceive(address recipient) external returns (bool);
    function getCollateralFeeBps(address collateral) external view returns (uint256, address);
    function updateCollateralFeeController() external;
    function globalLock(address caller) external;
    function globalUnlock() external;
    function maxCollateralWithdraw(address collateral, address account) external view returns (uint);
    function maxCollateralDeposit(address collateral) external view returns (uint);
}

interface ICollateralUnderlying {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Collateral {

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    ICollateralUnderlying public immutable asset;
    ICollateralCore public immutable core;
    uint public totalSupply;
    uint public lastAccrued;
    uint public lastBalance;
    uint public lastFeeBps;
    uint constant MINIMUM_LIQUIDITY = 10**3;
    uint constant MINIMUM_BALANCE = 10**3;
    uint256 internal constant MAX_UINT256 = 2**256 - 1;
    bytes32 public immutable DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    mapping(address => uint) public nonces;

    constructor(string memory _name, string memory _symbol, ICollateralUnderlying _asset, address _core) {
        name = _name;
        symbol = _symbol;
        asset = _asset;
        core = ICollateralCore(_core);
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
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

    function accrueFee() internal {
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return;
        uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
        try ICollateralCore(core).updateCollateralFeeController{gas: passedGas}() {} catch {}
        (uint currentFeeBps, address feeDestination) = core.getCollateralFeeBps(address(asset));
        uint feeBps = lastFeeBps;
        lastFeeBps = currentFeeBps;
        if(feeBps == 0) {
            lastAccrued = block.timestamp;
            return;
        }
        uint balance = lastBalance;
        uint256 fee = balance * feeBps * timeElapsed / 10000 / 365 days;
        if(fee > balance) fee = balance;
        if(balance - fee < MINIMUM_BALANCE) fee = balance > MINIMUM_BALANCE ? balance - MINIMUM_BALANCE : 0;
        if(fee == 0) return;
        lastAccrued = block.timestamp;
        asset.transfer(feeDestination, fee);
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

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : mulDivDown(shares, totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : mulDivUp(assets, supply, totalAssets());
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    function deposit(uint256 assets, address recipient) public lock returns (uint256 shares) {
        accrueFee();
        require(core.onCollateralDeposit(recipient, assets), "beforeCollateralDeposit");
        require((shares = previewDeposit(assets)) != 0, "zeroShares");
        balanceOf[recipient] += shares;
        totalSupply += shares;
        asset.transferFrom(msg.sender, address(this), assets);
        lastBalance = asset.balanceOf(address(this));
        emit Transfer(address(0), recipient, shares);
        emit Deposit(msg.sender, recipient, assets, shares);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : mulDivUp(shares, totalAssets(), supply);
    }

    function maxWithdraw(address owner) public view returns (uint256 assets) {
        uint shares = getCollateralOf(owner);
        if(shares > totalSupply - MINIMUM_LIQUIDITY) {
            shares = totalSupply - MINIMUM_LIQUIDITY;
        }
        assets = convertToAssets(shares);
        uint max = core.maxCollateralWithdraw(address(this), owner);
        assets = assets > max ? max : assets;
        if(assets > lastBalance - MINIMUM_BALANCE) {
            assets = lastBalance - MINIMUM_BALANCE;
        }
    }

    function maxRedeem(address owner) public view returns (uint256 assets) {
        uint shares = maxWithdraw(owner);
        return convertToAssets(shares);
    }

    function maxDeposit(address) public view returns (uint256 assets) {
        return core.maxCollateralDeposit(address(this));
    }

    function maxMint(address owner) public view returns (uint256 shares) {
        uint assets = maxDeposit(owner);
        return convertToShares(assets);
    }

    function mint(uint256 shares, address recipient) public lock returns (uint256 assets) {
        accrueFee();
        assets = previewMint(shares);
        require(core.onCollateralDeposit(recipient, assets), "beforeCollateralDeposit");
        balanceOf[recipient] += shares;
        totalSupply += shares;
        asset.transferFrom(msg.sender, address(this), assets);
        lastBalance = asset.balanceOf(address(this));
        emit Transfer(address(0), recipient, shares);
        emit Deposit(msg.sender, recipient, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public lock returns (uint256 shares) {
        accrueFee();
        require(core.onCollateralWithdraw(owner, assets), "beforeCollateralWithdraw");
        require(lastBalance - assets >= MINIMUM_BALANCE, "minimumBalance");
        shares = previewWithdraw(assets);
        require(totalSupply - shares >= MINIMUM_LIQUIDITY, "minimumLiquidity");
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        totalSupply -= shares;
        balanceOf[owner] -= shares;
        asset.transfer(receiver, assets);
        lastBalance = asset.balanceOf(address(this));
        emit Transfer(owner, address(0), shares);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) public lock returns (uint256 assets) {
        accrueFee();
        require(totalSupply - shares >= MINIMUM_LIQUIDITY, "minimumLiquidity");
        assets = previewRedeem(shares);
        require(core.onCollateralWithdraw(owner, assets), "beforeCollateralWithdraw");
        require(lastBalance - assets >= MINIMUM_BALANCE, "minimumBalance");
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        totalSupply -= shares;
        balanceOf[owner] -= shares;
        asset.transfer(receiver, assets);
        lastBalance = asset.balanceOf(address(this));
        emit Transfer(owner, address(0), shares);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function transfer(address recipient, uint256 shares) public lock returns (bool) {
        accrueFee();
        uint assets = convertToAssets(shares);
        require(core.onCollateralWithdraw(msg.sender, assets), "beforeCollateralWithdraw");
        balanceOf[msg.sender] -= shares;
        require(core.onCollateralReceive(recipient), "beforeCollateralReceive");
        balanceOf[recipient] += shares;
        emit Transfer(msg.sender, recipient, shares);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 shares) public lock returns (bool) {
        accrueFee();
        uint assets = convertToAssets(shares);
        require(core.onCollateralWithdraw(sender, assets), "beforeCollateralWithdraw");
        balanceOf[sender] -= shares;
        allowance[sender][msg.sender] -= shares;
        require(core.onCollateralReceive(recipient), "beforeCollateralReceive");
        balanceOf[recipient] += shares;
        emit Transfer(sender, recipient, shares);
        return true;
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
        accrueFee();
        require(msg.sender == address(core), "onlyCore");
        require(lastBalance - assets >= MINIMUM_BALANCE, "minimumBalance");
        uint shares = convertToShares(assets);
        require(totalSupply - shares >= MINIMUM_LIQUIDITY, "minimumLiquidity");
        totalSupply -= shares;
        balanceOf[account] -= shares;
        asset.transfer(to, assets);
        lastBalance = asset.balanceOf(address(this));
        emit Transfer(account, address(0), shares);
        emit Withdraw(msg.sender, to, account, shares, assets);
    }

    function pull(address _stuckToken, address dst, uint amount) external {
        require(msg.sender == address(core), "onlyCore");
        require(_stuckToken != address(asset), "cannotPullUnderlying");
        ICollateralUnderlying(_stuckToken).transfer(dst, amount);
    }

    function invalidateNonce() external {
        nonces[msg.sender]++;
    }    

    event Transfer(address indexed from, address indexed to, uint256 value);
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
