// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IPoolCore {
    function onPoolDeposit(uint256 amount) external returns (bool);
    function onPoolBorrow(address caller, uint256 amount) external returns (bool);
    function onPoolRepay(address caller, uint256 amount) external returns (bool);
    function getBorrowRateBps(address pool) external view returns (uint256, address);
    function updateInterestRateController() external;
    function globalLock(address caller) external;
    function globalUnlock() external;
    function poolsData(address pool) external view returns (bool enabled, uint depositCap, bool borrowPaused, bool borrowSuspended);
}

interface IPoolUnderlying {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Pool {

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    IPoolUnderlying public immutable asset;
    IPoolCore public immutable core;
    uint256 internal constant MAX_UINT256 = 2**256 - 1;
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public immutable PERMIT_TYPEHASH;
    bytes32 public immutable PERMIT_BORROW_TYPEHASH;
    uint public totalSupply;
    uint public debtSupply;
    uint public totalDebt;
    uint public lastAccrued;
    uint public lastBalance;
    uint public lastBorrowRate;
    uint constant MINIMUM_LIQUIDITY = 10**3;
    uint constant MINIMUM_BALANCE = 10**3;
    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => mapping (address => uint)) public borrowAllowance;
    mapping(address => uint) public debtSharesOf;
    mapping(address => uint) public nonces;

    constructor(
        string memory _name,
        string memory _symbol,
        IPoolUnderlying _asset,
        address _core
    ) {
        name = _name;
        symbol = _symbol;
        asset = _asset;
        core = IPoolCore(_core);
        PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        PERMIT_BORROW_TYPEHASH = keccak256("PermitBorrow(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
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

    function totalAssets() public view virtual returns (uint256) {
        return lastBalance + totalDebt;
    }

    function maxDeposit(address) public view returns (uint256) {
        (, uint depositCap,,) = core.poolsData(address(this));
        uint _totalAssets = totalAssets();
        if(_totalAssets >= depositCap) return 0;
        return depositCap - _totalAssets;
    }

    function maxMint(address) public view returns (uint256) {
        return convertToShares(maxDeposit(address(0)));
    }

    function maxWithdraw(address owner) public view returns (uint256 assets) {
        uint shares = balanceOf[owner];
        if(shares > totalSupply - MINIMUM_LIQUIDITY) {
            shares = totalSupply - MINIMUM_LIQUIDITY;
        }
        assets = convertToAssets(shares);
        if(assets > lastBalance - MINIMUM_BALANCE) {
            assets = lastBalance - MINIMUM_BALANCE;
        }
    }

    function maxRedeem(address owner) public view returns (uint256 shares) {
        shares = balanceOf[owner];
        if(shares > totalSupply - MINIMUM_LIQUIDITY) {
            shares = totalSupply - MINIMUM_LIQUIDITY;
        }
        uint assets = convertToAssets(shares);
        if(assets > lastBalance - MINIMUM_BALANCE) {
            assets = lastBalance - MINIMUM_BALANCE;
            shares = convertToShares(assets);
        }
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

    function deposit(uint256 assets, address recipient) public lock returns (uint256 shares) {
        require(core.onPoolDeposit(assets), "beforePoolDeposit");
        require((shares = previewDeposit(assets)) != 0, "zeroShares");
        balanceOf[recipient] += shares;
        totalSupply += shares;
        asset.transferFrom(msg.sender, address(this), assets);
        lastBalance = asset.balanceOf(address(this));
        emit Transfer(address(0), recipient, shares);
        emit Deposit(msg.sender, recipient, assets, shares);
    }

    function transfer(address recipient, uint256 shares) public returns (bool) {
        balanceOf[msg.sender] -= shares;
        balanceOf[recipient] += shares;
        emit Transfer(msg.sender, recipient, shares);
        return true;
    }

    function approve(address spender, uint256 shares) public returns (bool) {
        allowance[msg.sender][spender] = shares;
        emit Approval(msg.sender, spender, shares);
        return true;
    }

    function approveBorrow(address spender, uint256 amount) public returns (bool) {
        borrowAllowance[msg.sender][spender] = amount;
        emit BorrowApproval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 shares
    ) public returns (bool) {
        allowance[sender][msg.sender] -= shares;
        balanceOf[sender] -= shares;
        balanceOf[recipient] += shares;
        emit Transfer(sender, recipient, shares);
        return true;
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : mulDivUp(shares, totalAssets(), supply);
    }

    function mint(uint256 shares, address recipient) public lock returns (uint256 assets) {
        assets = previewMint(shares);
        require(core.onPoolDeposit(assets), "beforePoolDeposit");
        balanceOf[recipient] += shares;
        totalSupply += shares;
        asset.transferFrom(msg.sender, address(this), assets);
        lastBalance = asset.balanceOf(address(this));
        emit Transfer(address(0), recipient, shares);
        emit Deposit(msg.sender, recipient, assets, shares);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : mulDivUp(assets, supply, totalAssets());
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public lock returns (uint256 shares) {
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

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : mulDivDown(shares, totalAssets(), supply);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    function redeem(uint256 shares, address receiver, address owner) public lock virtual returns (uint256 assets) {
        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "zeroAssets");
        require(lastBalance - assets >= MINIMUM_BALANCE, "minimumBalance");
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

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'permitExpired');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'Pool: INVALID_SIGNATURE');
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function permitBorrow(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'permitExpired');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_BORROW_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'Pool: INVALID_SIGNATURE');
        borrowAllowance[owner][spender] = value;
        emit BorrowApproval(owner, spender, value);
    }

    function accrueInterest() internal {
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return;
        uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
        try IPoolCore(core).updateInterestRateController{gas: passedGas}() {} catch {}
        (uint borrowRateBps, address borrowRateDestination) = core.getBorrowRateBps(address(this));
        uint256 interest = totalDebt * lastBorrowRate * timeElapsed / 10000 / 365 days;
        uint shares = convertToDebtShares(interest);
        if(shares == 0) return;
        lastAccrued = block.timestamp;
        totalDebt += interest;
        debtSupply += shares;
        lastBorrowRate = borrowRateBps;
        debtSharesOf[borrowRateDestination] += shares;
    }

    function previewBorrow(uint256 assets) public view returns (uint256) {
        uint256 supply = debtSupply; // Saves an extra SLOAD if debtSupply is non-zero.

        return supply == 0 ? assets : mulDivDown(assets, debtSupply, totalDebt);
    }

    function borrow(uint256 amount, address owner, address recipient) public lock {
        accrueInterest();
        require(core.onPoolBorrow(owner, amount), "beforePoolBorrow");
        require(lastBalance - amount >= MINIMUM_BALANCE, "minimumBalance");
        if (msg.sender != owner) {
            uint256 allowed = borrowAllowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) borrowAllowance[owner][msg.sender] = allowed - amount;
        }
        uint debtShares;
        require((debtShares = previewBorrow(amount)) != 0, "zeroShares");
        debtSharesOf[owner] += debtShares;
        debtSupply += debtShares;
        totalDebt += amount;
        asset.transfer(recipient, amount);
        lastBalance = asset.balanceOf(address(this));
    }

    function previewRepay(uint256 assets) public view returns (uint256) {
        uint256 supply = debtSupply; // Saves an extra SLOAD if debtSupply is non-zero.

        return supply == 0 ? assets : mulDivUp(assets, debtSupply, totalDebt);
    }

    function repay(address to, uint amount) public lock {
        accrueInterest();
        require(core.onPoolRepay(to, amount), "beforePoolRepay");
        if(amount == type(uint256).max) amount = getDebtOf(to);
        uint debtShares;
        require((debtShares = previewRepay(amount)) != 0, "zeroShares");
        debtSharesOf[to] -= debtShares;
        debtSupply -= debtShares;
        totalDebt -= amount;
        asset.transferFrom(msg.sender, address(this), amount);
        lastBalance = asset.balanceOf(address(this));
    }

    function writeOff(address account) public lock {
        accrueInterest();
        require(msg.sender == address(core), "onlyCore");
        uint debtShares = debtSharesOf[msg.sender];
        uint debt = convrtToDebtAssets(debtShares);
        debtSharesOf[account] -= debtShares;
        debtSupply -= debtShares;
        totalDebt -= debt;
    }

    function getAssetsOf(address account) public view returns (uint) {
        return convertToAssets(balanceOf[account]);
    }

    function convertToDebtAssets(uint256 debtShares) public view returns (uint256) {
        uint256 supply = debtSupply; // Saves an extra SLOAD if debtSupply is non-zero.

        return supply == 0 ? debtShares : mulDivDown(debtShares, totalDebt, debtSupply);
    }

    function convertToDebtShares(uint256 debtAssets) public view returns (uint256) {
        uint256 supply = debtSupply; // Saves an extra SLOAD if debtSupply is non-zero.

        return supply == 0 ? debtAssets : mulDivUp(debtAssets, debtSupply, totalDebt);
    }

    function getDebtOf(address account) public view returns (uint) {
        if(debtSupply == 0) return 0;
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return convertToDebtAssets(debtSharesOf[account]);
        (uint borrowRateBps,) = core.getBorrowRateBps(address(this));
        uint256 interest = totalDebt * borrowRateBps * timeElapsed / 10000 / 365 days;
        uint shares = convertToDebtShares(interest);
        if(shares == 0) return convertToDebtAssets(debtSharesOf[account]);
        return mulDivDown(debtSharesOf[account], totalDebt + interest, debtSupply + shares);
    }

    function getSupplied() external view returns (uint) {
        return totalAssets();
    }

    function pull(address _stuckToken, address dst, uint amount) external {
        require(msg.sender == address(core), "onlyCore");
        require(_stuckToken != address(asset), "cannotPullUnderlying");
        IPoolUnderlying(_stuckToken).transfer(dst, amount);
    }

    function invalidateNonce() external {
        nonces[msg.sender]++;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BorrowApproval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
}