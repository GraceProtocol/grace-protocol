// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IPoolCore {
    function onPoolDeposit(address caller, address recipient, uint256 amount) external returns (bool);
    function onPoolWithdraw(address caller, uint256 amount) external returns (bool);
    function onPoolBorrow(address caller, uint256 amount) external returns (bool);
    function onPoolRepay(address caller, address to, uint256 amount) external returns (bool);
    function getBorrowRateBps(address pool) external view returns (uint256, address);
    function updateInterestRateModel() external;
}

interface IPoolUnderlying {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Pool {

    IPoolUnderlying public immutable token;
    IPoolCore public immutable core;
    uint public totalSupply;
    uint public debtSupply;
    uint public totalDebt;
    uint public lastAccrued;
    uint public lastBalance;
    uint public lastBorrowRate;
    uint constant MINIMUM_LIQUIDITY = 10**3;
    uint constant MINIMUM_BALANCE = 10**3;
    uint constant sqrtMaxUint = 340282366920938463463374607431768211455;
    mapping (address => uint) public balanceOf;
    mapping(address => uint) public debtSharesOf;

    constructor(IPoolUnderlying _token) {
        token = _token;
        core = IPoolCore(msg.sender);
    }

    function deposit(address recipient, uint256 amount) public {
        require(core.onPoolDeposit(msg.sender, recipient, amount), "beforePoolDeposit");
        uint shares;
        if(totalSupply == 0) {
            balanceOf[address(0)] = MINIMUM_LIQUIDITY;
            shares = amount - MINIMUM_LIQUIDITY;
            totalSupply = amount;
        } else {
            shares = amount * totalSupply / (lastBalance + totalDebt);
            totalSupply += shares;
        }
        require(shares > 0, "zeroShares");
        uint sharesBefore = balanceOf[recipient];
        uint newShares = sharesBefore + shares;
        require(newShares <= sqrtMaxUint, "overflow");
        balanceOf[recipient] = newShares;
        token.transferFrom(msg.sender, address(this), amount);
        lastBalance = token.balanceOf(address(this));
    }

    function withdraw(uint256 amount) public {
        require(core.onPoolWithdraw(msg.sender, amount), "beforePoolWithdraw");
        require(lastBalance - amount >= MINIMUM_BALANCE, "minimumBalance");
        uint shares;
        if(amount == type(uint256).max) {
            shares = balanceOf[msg.sender];
            amount = shares * (lastBalance + totalDebt) / totalSupply;
        } else {
            shares = amount * totalSupply / (lastBalance + totalDebt);
        }
        require(shares > 0, "zeroShares");
        totalSupply -= shares;
        balanceOf[msg.sender] -= shares;
        token.transfer(msg.sender, amount);
        lastBalance = token.balanceOf(address(this));
    }

    function accrueInterest() internal {
        uint passedGas = gasleft() > 1000000 ? 1000000 : gasleft(); // protect against out of gas reverts
        try IPoolCore(core).updateInterestRateModel{gas: passedGas}() {} catch {}
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return;
        (uint borrowRateBps, address borrowRateDestination) = core.getBorrowRateBps(address(this));
        uint256 interest = totalDebt * lastBorrowRate * timeElapsed / 10000 / 365 days;
        uint shares = interest * totalSupply / (lastBalance + totalDebt);
        if(shares == 0) return;
        lastAccrued = block.timestamp;
        totalDebt += interest;
        debtSupply += shares;
        lastBorrowRate = borrowRateBps;
        debtSharesOf[borrowRateDestination] += shares;
    }

    function borrow(uint256 amount) public {
        accrueInterest();
        require(core.onPoolBorrow(msg.sender, amount), "beforePoolBorrow");
        require(lastBalance - amount >= MINIMUM_BALANCE, "minimumBalance");
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
        lastBalance = token.balanceOf(address(this));
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
        lastBalance = token.balanceOf(address(this));
    }

    function writeOff(address account) public {
        accrueInterest();
        require(msg.sender == address(core), "onlyCore");
        uint debtShares = debtSharesOf[msg.sender];
        uint debt = debtShares * totalDebt / debtSupply;
        debtSharesOf[account] -= debtShares;
        debtSupply -= debtShares;
        totalDebt -= debt;
    }

    function getAssetsOf(address account) public view returns (uint) {
        if(totalSupply == 0) return 0;
        return balanceOf[account] * (lastBalance + totalDebt) / totalSupply;
    }

    function getDebtOf(address account) public view returns (uint) {
        if(debtSupply == 0) return 0;
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return debtSharesOf[account] * totalDebt / debtSupply;
        (uint borrowRateBps,) = core.getBorrowRateBps(address(this));
        uint256 interest = totalDebt * borrowRateBps * timeElapsed / 10000 / 365 days;
        uint shares = interest * totalSupply / (lastBalance + totalDebt);
        if(shares == 0) return debtSharesOf[account] * totalDebt / debtSupply;
        return debtSharesOf[account] * (totalDebt + interest) / (debtSupply + shares);
    }

    function getSupplied() external view returns (uint) {
        return lastBalance + totalDebt;
    }
}