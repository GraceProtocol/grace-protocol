// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface ICore {
    function onPoolDeposit(address caller, address recipient, uint256 amount) external returns (bool);
    function onPoolWithdraw(address caller, uint256 amount) external returns (bool);
    function onPoolBorrow(address caller, uint256 amount) external returns (bool);
    function onPoolRepay(address caller, address to, uint256 amount) external returns (bool);
    function getBorrowRateBps(address pool) external view returns (uint256, address);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract BasePool {

    IERC20 public immutable token;
    ICore public immutable core;
    uint public totalSupply;
    uint public debtSupply;
    uint public totalDebt;
    uint public lastAccrued;
    uint constant MINIMUM_LIQUIDITY = 10**3;
    uint constant MINIMUM_BALANCE = 10**3;
    uint constant sqrtMaxUint = 340282366920938463463374607431768211455;
    mapping (address => uint) public balanceOf;
    mapping(address => uint) public debtSharesOf;

    constructor(IERC20 _token) {
        token = _token;
        core = ICore(msg.sender);
    }

    function deposit(address recipient, uint256 amount) public {
        require(core.onPoolDeposit(msg.sender, recipient, amount), "beforePoolDeposit");
        uint shares;
        if(totalSupply == 0) {
            balanceOf[address(0)] = MINIMUM_LIQUIDITY;
            shares = amount - MINIMUM_LIQUIDITY;
            totalSupply = amount;
        } else {
            shares = amount * totalSupply / (token.balanceOf(address(this)) + totalDebt);
            totalSupply += shares;
        }
        require(shares > 0, "zeroShares");
        uint sharesBefore = balanceOf[recipient];
        uint newShares = sharesBefore + shares;
        require(newShares <= sqrtMaxUint, "overflow");
        balanceOf[recipient] = newShares;
        token.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public {
        require(core.onPoolWithdraw(msg.sender, amount), "beforePoolWithdraw");
        require(token.balanceOf(address(this)) - amount >= MINIMUM_BALANCE, "minimumBalance");
        uint shares;
        if(amount == type(uint256).max) {
            shares = balanceOf[msg.sender];
            amount = shares * (token.balanceOf(address(this)) + totalDebt) / totalSupply;
        } else {
            shares = amount * totalSupply / (token.balanceOf(address(this)) + totalDebt);
        }
        require(shares > 0, "zeroShares");
        totalSupply -= shares;
        balanceOf[msg.sender] -= shares;
        token.transfer(msg.sender, amount);
    }

    function accrueInterest() public {
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return;
        (uint borrowRateBps, address borrowRateDestination) = core.getBorrowRateBps(address(this));
        uint256 interest = totalDebt * borrowRateBps * timeElapsed / 10000 / 365 days;
        uint shares = interest * totalSupply / (token.balanceOf(address(this)) + totalDebt);
        if(shares == 0) return;
        lastAccrued = block.timestamp;
        totalDebt += interest;
        debtSupply += shares;
        debtSharesOf[borrowRateDestination] += shares;
    }

    function borrow(uint256 amount) public {
        accrueInterest();
        require(core.onPoolBorrow(msg.sender, amount), "beforePoolBorrow");
        require(token.balanceOf(address(this)) - amount >= MINIMUM_BALANCE, "minimumBalance");
        uint debtShares;
        if(debtSupply == 0) {
            debtShares = amount;
        } else {
            debtShares = amount * debtSupply / totalDebt;
        }
        require(debtShares > 0, "zeroShares");
        debtSharesOf[msg.sender] += debtShares;
        debtSupply += debtShares;
        totalDebt += amount;
        token.transfer(msg.sender, amount);
    }

    function repay(address to, uint amount) public {
        accrueInterest();
        require(core.onPoolRepay(msg.sender, to, amount), "beforePoolRepay");
        uint debtShares;
        if(amount == type(uint256).max) {
            debtShares = debtSharesOf[msg.sender];
            amount = debtShares * totalDebt / debtSupply;
        } else {
            debtShares = amount * debtSupply / totalDebt;
        }
        debtSharesOf[msg.sender] -= debtShares;
        debtSupply -= debtShares;
        totalDebt -= amount;
        token.transferFrom(msg.sender, address(this), amount);
    }

    function writeOff(address account, uint amount) public {
        accrueInterest();
        require(msg.sender == address(core), "onlyCore");
        uint debtShares;
        if(amount == type(uint256).max) {
            debtShares = debtSharesOf[msg.sender];
            amount = debtShares * totalDebt / debtSupply;
        } else {
            debtShares = amount * debtSupply / totalDebt;
        }
        debtSharesOf[account] -= debtShares;
        debtSupply -= debtShares;
        totalDebt -= amount;
    }

    function getAssetsOf(address account) public view returns (uint) {
        if(totalSupply == 0) return 0;
        return balanceOf[account] * (token.balanceOf(address(this)) + totalDebt) / totalSupply;
    }

    function getDebtOf(address account) public view returns (uint) {
        if(debtSupply == 0) return 0;
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return debtSharesOf[account] * totalDebt / debtSupply;
        (uint borrowRateBps,) = core.getBorrowRateBps(address(this));
        uint256 interest = totalDebt * borrowRateBps * timeElapsed / 10000 / 365 days;
        uint shares = interest * totalSupply / (token.balanceOf(address(this)) + totalDebt);
        if(shares == 0) return debtSharesOf[account] * totalDebt / debtSupply;
        return debtSharesOf[account] * (totalDebt + interest) / (debtSupply + shares);
    }

    function getSupplied() external view returns (uint) {
        return token.balanceOf(address(this)) + totalDebt;
    }
}