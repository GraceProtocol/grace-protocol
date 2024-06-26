// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IPoolCore {
    function feeDestination() external view returns (address);
    function onPoolDeposit(uint256 amount) external view returns (bool);
    function onPoolBorrow(address caller, uint256 amount) external returns (bool);
    function onPoolRepay(address caller, uint256 amount) external returns (bool);
    function getBorrowRateBps(address pool, uint util, uint lastBorrowRate, uint lastAccrued) external view returns (uint256);
    function globalLock(address caller) external;
    function globalUnlock() external;
    function poolsData(address pool) external view returns (bool enabled, uint depositCap, uint ema, uint lastUpdate);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

contract Pool {

    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    IERC20 public immutable asset;
    bool public immutable isWETH;
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
    uint public totalReferrerShares;
    uint public rewardIndexMantissa;
    uint constant MANTISSA = 1e18;
    uint constant MINIMUM_BALANCE = 10**3;
    uint constant REF_FEE_BPS = 1000; // 10%
    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => mapping (address => uint)) public borrowAllowance;
    mapping(address => uint) public debtSharesOf;
    mapping(address => uint) public nonces;
    mapping(address => address) public borrowerReferrers;
    mapping(address => uint) public referrerShares;
    mapping(address => uint) public referrerIndexMantissa;
    mapping(address => uint) public accruedReferrerRewards;

    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _asset,
        bool _isWETH,
        address _core
    ) {
        name = _name;
        symbol = _symbol;
        asset = _asset;
        isWETH = _isWETH;
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

    modifier onlyWETH {
        require(isWETH, "onlyWETH");
        _;
    }

    receive() external payable {}

    function accrueInterest() internal returns (uint _lastAccrued) {
        _lastAccrued = lastAccrued;
        uint256 timeElapsed = block.timestamp - _lastAccrued;
        // if timeElapsed is 0, it means that the interest has already been accrued for the current block
        if(timeElapsed == 0) return _lastAccrued;
        // skip interest accrual if the borrow rate is 0
        if(lastBorrowRate == 0) {
            lastAccrued = block.timestamp;
            return _lastAccrued;
        }
        // borrow rate is in basis points, timeElapsed is in seconds
        uint256 interest = totalDebt * lastBorrowRate * timeElapsed / 10000 / 365 days;
        uint shares = convertToShares(interest);
        // if shares is 0, it means that the interest is too small to be accrued
        if(shares == 0) return _lastAccrued;
        lastAccrued = block.timestamp;
        totalDebt += interest;
        totalSupply += shares;
        address borrowRateDestination = core.feeDestination();
        // before minting the interest to the fee recipient, we need to deduct the referrer rewards
        uint referrersReward;
        // skip referrer rewards if there are no referrers or if the debt supply is 0 to avoid division by zero
        if(totalReferrerShares > 0 && debtSupply > 0) {
            // only deduct REF_FEE_BPS from the portion of interest that has a referrer
            // e.g. if 50% of users have a referrer, then REF_FEE_BPS should be deducted from 50% of the interest
            // if no users have a referrer, then the full interest is minted to the fee recipient
            referrersReward = shares * totalReferrerShares * REF_FEE_BPS / debtSupply / 10000;
            // temporarily mint the referrer rewards to the pool in the form of shares for referrers to claim
            balanceOf[address(this)] += referrersReward;
            emit Transfer(address(0), address(this), referrersReward);
            // update the reward index for referrers
            rewardIndexMantissa += referrersReward * MANTISSA / totalReferrerShares;
        }
        // deduct the referrer rewards from the interest
        uint fee = referrersReward > shares ? 0 : shares - referrersReward;
        // mint the interest to the fee recipient
        balanceOf[borrowRateDestination] += fee;
        emit Transfer(address(0), borrowRateDestination, fee);
    }

    function updateReferrer(address referrer) internal {
        // deltaIndex is the difference between the current reward index and the last reward index for the referrer
        uint deltaIndex = rewardIndexMantissa - referrerIndexMantissa[referrer];
        uint bal = referrerShares[referrer];
        uint referrerDelta = bal * deltaIndex;
        referrerIndexMantissa[referrer] = rewardIndexMantissa;
        // divide by MANTISSA because rewardIndexMantissa is scaled by MANTISSA
        accruedReferrerRewards[referrer] += referrerDelta / MANTISSA;
    }

    function updateBorrowRate(uint _lastAccrued) internal {
        uint _totalAssets = totalAssets();
        uint util = _totalAssets == 0 ? 0 : totalDebt * 10000 / _totalAssets;
        lastBorrowRate = core.getBorrowRateBps(address(this), util, lastBorrowRate, _lastAccrued);
    }

    function totalAssets() public view returns (uint256) {
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
        assets = convertToAssets(shares);
        if(assets > lastBalance - MINIMUM_BALANCE) {
            assets = lastBalance - MINIMUM_BALANCE;
        }
    }

    function maxRedeem(address owner) public view returns (uint256 shares) {
        shares = balanceOf[owner];
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
        uint _lastAccrued = accrueInterest();
        require(core.onPoolDeposit(assets), "beforePoolDeposit");
        require((shares = previewDeposit(assets)) != 0, "zeroShares");
        balanceOf[recipient] += shares;
        totalSupply += shares;
        asset.safeTransferFrom(msg.sender, address(this), assets);
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Transfer(address(0), recipient, shares);
        emit Deposit(msg.sender, recipient, assets, shares);
        updateBorrowRate(_lastAccrued);
    }

    function deposit(uint256 assets) public returns (uint256 shares) {
        return deposit(assets, msg.sender);
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
        uint _lastAccrued = accrueInterest();
        assets = previewMint(shares);
        require(core.onPoolDeposit(assets), "beforePoolDeposit");
        balanceOf[recipient] += shares;
        totalSupply += shares;
        asset.safeTransferFrom(msg.sender, address(this), assets);
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Transfer(address(0), recipient, shares);
        emit Deposit(msg.sender, recipient, assets, shares);
        updateBorrowRate(_lastAccrued);
    }

    function mint(uint256 shares) public returns (uint256 assets) {
        return mint(shares, msg.sender);
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
        uint _lastAccrued = accrueInterest();
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
        emit Transfer(owner, address(0), shares);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        updateBorrowRate(_lastAccrued);
    }

    function withdraw(uint256 assets) public returns (uint256 shares) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : mulDivDown(shares, totalAssets(), supply);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    function redeem(uint256 shares, address receiver, address owner) public lock returns (uint256 assets) {
        uint _lastAccrued = accrueInterest();
        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "zeroAssets");
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        totalSupply -= shares;
        balanceOf[owner] -= shares;
        asset.safeTransfer(receiver, assets);
        lastBalance = asset.balanceOf(address(this));
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        emit Transfer(owner, address(0), shares);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        updateBorrowRate(_lastAccrued);
    }

    function redeem(uint256 shares) public returns (uint256 assets) {
        return redeem(shares, msg.sender, msg.sender);
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
        address recoveredAddress = digest.recover(v, r, s);
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
        address recoveredAddress = digest.recover(v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'Pool: INVALID_SIGNATURE');
        borrowAllowance[owner][spender] = value;
        emit BorrowApproval(owner, spender, value);
    }

    function previewBorrow(uint256 assets) public view returns (uint256) {
        uint256 supply = debtSupply; // Saves an extra SLOAD if debtSupply is non-zero.

        return supply == 0 ? assets : mulDivDown(assets, debtSupply, totalDebt);
    }

    function borrow(uint256 amount, address referrer, address owner) public lock {
        uint _lastAccrued = accrueInterest();
        require(core.onPoolBorrow(owner, amount), "beforePoolBorrow");
        if (msg.sender != owner) {
            uint256 allowed = borrowAllowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) borrowAllowance[owner][msg.sender] = allowed - amount;
        }
        uint debtShares;
        require((debtShares = previewBorrow(amount)) != 0, "zeroShares");
        if(borrowerReferrers[owner] != address(0)) {
            updateReferrer(borrowerReferrers[owner]);
            referrerShares[borrowerReferrers[owner]] -= debtSharesOf[owner];
            totalReferrerShares -= debtSharesOf[owner];
        }
        debtSharesOf[owner] += debtShares;
        if(referrer != address(0)) {
            updateReferrer(referrer);
            referrerShares[referrer] += debtSharesOf[owner];
            totalReferrerShares += debtSharesOf[owner];
        }
        borrowerReferrers[owner] = referrer;
        debtSupply += debtShares;
        totalDebt += amount;
        asset.safeTransfer(msg.sender, amount);
        lastBalance = asset.balanceOf(address(this));
        emit Borrow(owner, amount, debtShares);
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        updateBorrowRate(_lastAccrued);
    }

    function borrow(uint256 amount, address referrer) public {
        borrow(amount, referrer, msg.sender);
    }

    function borrow(uint256 amount) public {
        borrow(amount, borrowerReferrers[msg.sender], msg.sender);
    }

    function borrowETH(uint256 amount, address referrer, address owner) public lock onlyWETH {
        uint _lastAccrued = accrueInterest();
        require(core.onPoolBorrow(owner, amount), "beforePoolBorrow");
        if (msg.sender != owner) {
            uint256 allowed = borrowAllowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) borrowAllowance[owner][msg.sender] = allowed - amount;
        }
        uint debtShares;
        require((debtShares = previewBorrow(amount)) != 0, "zeroShares");
        if(borrowerReferrers[owner] != address(0)) {
            updateReferrer(borrowerReferrers[owner]);
            referrerShares[borrowerReferrers[owner]] -= debtSharesOf[owner];
            totalReferrerShares -= debtSharesOf[owner];
        }
        debtSharesOf[owner] += debtShares;
        if(referrer != address(0)) {
            updateReferrer(referrer);
            referrerShares[referrer] += debtSharesOf[owner];
            totalReferrerShares += debtSharesOf[owner];
        }
        borrowerReferrers[owner] = referrer;
        debtSupply += debtShares;
        totalDebt += amount;
        IWETH(address(asset)).withdraw(amount);
        lastBalance = asset.balanceOf(address(this));
        emit Borrow(owner, amount, debtShares);
        require(lastBalance >= MINIMUM_BALANCE, "minimumBalance");
        updateBorrowRate(_lastAccrued);
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    function borrowETH(uint256 amount, address referrer) public {
        borrowETH(amount, referrer, msg.sender);
    }

    function borrowETH(uint256 amount) public {
        borrowETH(amount, borrowerReferrers[msg.sender], msg.sender);
    }

    function previewRepay(uint256 assets) public view returns (uint256) {
        uint256 supply = debtSupply; // Saves an extra SLOAD if debtSupply is non-zero.

        return supply == 0 ? assets : mulDivUp(assets, debtSupply, totalDebt);
    }

    function repay(address to, uint amount) public lock {
        uint _lastAccrued = accrueInterest();
        if(amount == type(uint256).max) amount = getDebtOf(to);
        require(core.onPoolRepay(to, amount), "beforePoolRepay");
        uint debtShares;
        require((debtShares = previewRepay(amount)) != 0, "zeroShares");
        if(borrowerReferrers[to] != address(0)) {
            updateReferrer(borrowerReferrers[to]);
            referrerShares[borrowerReferrers[to]] -= debtShares;
            totalReferrerShares -= debtShares;
        }
        debtSharesOf[to] -= debtShares;
        debtSupply -= debtShares;
        totalDebt -= amount;
        asset.safeTransferFrom(msg.sender, address(this), amount);
        lastBalance = asset.balanceOf(address(this));
        emit Repay(to, amount, debtShares);
        updateBorrowRate(_lastAccrued);
    }

    function repay(uint amount) public {
        repay(msg.sender, amount);
    }

    function repayETH(address to) public payable lock onlyWETH {
        uint _lastAccrued = accrueInterest();
        uint amount = msg.value;
        uint debt = getDebtOf(to);
        uint refund;
        if(amount > debt) {
            refund = amount - debt;
            amount = debt;
        }
        require(core.onPoolRepay(to, amount), "beforePoolRepay");
        uint debtShares;
        require((debtShares = previewRepay(amount)) != 0, "zeroShares");
        if(borrowerReferrers[to] != address(0)) {
            updateReferrer(borrowerReferrers[to]);
            referrerShares[borrowerReferrers[to]] -= debtShares;
            totalReferrerShares -= debtShares;
        }
        debtSharesOf[to] -= debtShares;
        debtSupply -= debtShares;
        totalDebt -= amount;
        IWETH(address(asset)).deposit{value: amount}();
        lastBalance = asset.balanceOf(address(this));
        emit Repay(to, amount, debtShares);
        updateBorrowRate(_lastAccrued);
        if(refund > 0) {
            (bool success,) = msg.sender.call{value: refund}("");
            require(success, "ETH transfer failed");
        }
    }

    function repayETH() public payable {
        repayETH(msg.sender);
    }

    function writeOff(address account) public lock {
        uint _lastAccrued = accrueInterest();
        require(msg.sender == address(core), "onlyCore");
        uint debtShares = debtSharesOf[account];
        uint debt = convertToDebtAssets(debtShares);
        if(borrowerReferrers[account] != address(0)) {
            updateReferrer(borrowerReferrers[account]);
            referrerShares[borrowerReferrers[account]] -= debtShares;
            totalReferrerShares -= debtShares;
        }
        debtSharesOf[account] -= debtShares;
        debtSupply -= debtShares;
        totalDebt -= debt;
        emit WriteOff(account, debt, debtShares);
        updateBorrowRate(_lastAccrued);
    }

    function claimReferralRewards(address user) external {
        accrueInterest();
        updateReferrer(user);
        uint amount = accruedReferrerRewards[user];
        accruedReferrerRewards[user] = 0;
        IERC20(address(this)).transfer(user, amount);
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
        // accrue interest to the current block, same as accrueInterest()
        if(debtSupply == 0) return 0;
        uint256 timeElapsed = block.timestamp - lastAccrued;
        // if timeElapsed is 0, it means that the interest has already been accrued for the current block
        if(timeElapsed == 0) return convertToDebtAssets(debtSharesOf[account]);
        // lastBorrowRate is in basis points, timeElapsed is in seconds
        uint256 interest = totalDebt * lastBorrowRate * timeElapsed / 10000 / 365 days;
        uint shares = convertToDebtShares(interest);
        // if shares is 0, it means that the interest is too small to be accrued
        if(shares == 0) return convertToDebtAssets(debtSharesOf[account]);
        // we use mulDivUp to round down the debt shares
        return mulDivDown(debtSharesOf[account], totalDebt + interest, debtSupply);
    }

    function pull(address _stuckToken, address dst, uint amount) external {
        require(msg.sender == address(core), "onlyCore");
        require(_stuckToken != address(asset), "cannotPullUnderlying");
        require(_stuckToken != address(this), "cannotPullSelf");
        IERC20(_stuckToken).safeTransfer(dst, amount);
    }

    function invalidateNonce() external {
        nonces[msg.sender]++;
    }

    event Borrow(address indexed borrower, uint amount, uint debtShares);
    event Repay(address indexed borrower, uint amount, uint debtShares);
    event WriteOff(address indexed borrower, uint amount, uint debtShares);
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