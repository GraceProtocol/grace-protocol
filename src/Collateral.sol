// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface ICollateralCore {
    function onCollateralDeposit(address caller, address recipient, uint256 amount) external returns (bool);
    function onCollateralWithdraw(address caller, uint256 amount) external returns (bool);
    function getCollateralFeeBps(address collateral) external view returns (uint256, address);
    function updateCollateralFeeController() external;
    function globalLock(address caller) external;
    function globalUnlock() external;
}

interface ICollateralUnderlying {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Collateral {

    ICollateralUnderlying public immutable token;
    ICollateralCore public immutable core;
    uint public sharesSupply;
    uint public lastAccrued;
    uint public lastBalance;
    uint public lastFeeBps;
    mapping (address => uint) public sharesOf;
    uint constant sqrtMaxUint = 340282366920938463463374607431768211455;
    uint constant MINIMUM_LIQUIDITY = 10**3;
    uint constant MINIMUM_BALANCE = 10**3;

    constructor(ICollateralUnderlying _token) {
        token = _token;
        core = ICollateralCore(msg.sender);
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
        (uint currentFeeBps, address feeDestination) = core.getCollateralFeeBps(address(token));
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
        token.transfer(feeDestination, fee);
    }

    function deposit(address recipient, uint256 amount) public lock {
        accrueFee();
        require(core.onCollateralDeposit(msg.sender, recipient, amount), "beforeCollateralDeposit");
        uint shares;
        if(sharesSupply == 0) {
            sharesOf[address(0)] = MINIMUM_LIQUIDITY;
            shares = amount - MINIMUM_LIQUIDITY;
            sharesSupply = amount;
        } else {
            shares = amount * sharesSupply / lastBalance;
            sharesSupply += shares;
        }
        require(shares > 0, "zeroShares");
        uint sharesBefore = sharesOf[recipient];
        uint newShares = sharesBefore + shares;
        require(newShares <= sqrtMaxUint, "overflow");
        sharesOf[recipient] = newShares;
        token.transferFrom(msg.sender, address(this), amount);
        lastBalance = token.balanceOf(address(this));
    }

    function withdraw(uint256 amount) public lock {
        accrueFee();
        require(core.onCollateralWithdraw(msg.sender, amount), "beforeCollateralWithdraw");
        require(lastBalance - amount >= MINIMUM_BALANCE, "minimumBalance");
        uint shares;
        if(amount == type(uint256).max) {
            shares = sharesOf[msg.sender];
            amount = shares * lastBalance / sharesSupply;
        } else {
            shares = amount * sharesSupply / lastBalance;
        }
        require(shares > 0, "zeroShares");
        sharesSupply -= shares;
        sharesOf[msg.sender] -= shares;
        token.transfer(msg.sender, amount);
        lastBalance = token.balanceOf(address(this));
    }

    function getCollateralOf(address account) public view returns (uint256) {
        if(sharesSupply == 0) return 0;
        uint256 timeElapsed = block.timestamp - lastAccrued;
        (uint feeBps,) = core.getCollateralFeeBps(address(token));
        uint balance = lastBalance;
        uint256 fee = balance * feeBps * timeElapsed / 10000 / 365 days;
        if(fee > balance) fee = balance;
        if(balance - fee < MINIMUM_BALANCE) fee = balance > MINIMUM_BALANCE ? balance - MINIMUM_BALANCE : 0;
        return (balance - fee) * sharesOf[account] / sharesSupply;
    }

    function seize(address account, uint256 amount, address to) public lock {
        accrueFee();
        require(msg.sender == address(core), "onlyCore");
        require(lastBalance - amount >= MINIMUM_BALANCE, "minimumBalance");
        uint shares = amount * sharesSupply / lastBalance;
        require(shares > 0, "zeroShares");
        sharesSupply -= shares;
        sharesOf[account] -= shares;
        token.transfer(to, amount);
        lastBalance = token.balanceOf(address(this));
    }

    function getTotalCollateral() external view returns (uint256) {
        return lastBalance;
    }

    function pull(address _stuckToken, address dst, uint amount) external {
        require(msg.sender == address(core), "onlyCore");
        require(_stuckToken != address(token), "cannotPullUnderlying");
        ICollateralUnderlying(_stuckToken).transfer(dst, amount);
    }
    
}
