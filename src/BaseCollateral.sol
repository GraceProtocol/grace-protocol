// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface ICore {
    function onCollateralDeposit(address caller, address recipient, uint256 amount) external returns (bool);
    function onCollateralWithdraw(address caller, uint256 amount) external returns (bool);
    function getCollateralFeeBps(address collateral) external view returns (uint256, address);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract BaseCollateral {

    IERC20 public token;
    ICore public core;
    uint public sharesSupply;
    uint public lastAccrued;
    mapping (address => uint) public sharesOf;
    uint constant sqrtMaxUint = 340282366920938463463374607431768211455;
    uint constant MINIMUM_LIQUIDITY = 10**3;
    uint constant MINIMUM_BALANCE = 10**3;

    constructor(IERC20 _token, ICore _core) {
        token = _token;
        core = _core;
    }

    function accrueFee() public {
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if(timeElapsed == 0) return;
        (uint feeBps, address feeDestination) = core.getCollateralFeeBps(address(token));
        if(feeBps == 0) return;
        uint balance = token.balanceOf(address(this));
        uint256 fee = balance * feeBps * timeElapsed / 10000 / 365 days;
        if(fee > balance) fee = balance;
        if(balance - fee < MINIMUM_BALANCE) fee = balance - MINIMUM_BALANCE;
        if(fee == 0) return;
        lastAccrued = block.timestamp;
        token.transfer(feeDestination, fee);
    }

    function deposit(address recipient, uint256 amount) public {
        accrueFee();
        require(core.onCollateralDeposit(msg.sender, recipient, amount), "beforeCollateralDeposit");
        uint shares;
        if(sharesSupply == 0) {
            sharesOf[address(0)] = MINIMUM_LIQUIDITY;
            shares = amount - MINIMUM_LIQUIDITY;
            sharesSupply = amount;
        } else {
            shares = amount * sharesSupply / token.balanceOf(address(this));
            sharesSupply += shares;
        }
        require(shares > 0, "zeroShares");
        uint sharesBefore = sharesOf[recipient];
        uint newShares = sharesBefore + shares;
        require(newShares <= sqrtMaxUint, "overflow");
        sharesOf[recipient] = newShares;
        token.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public {
        accrueFee();
        require(core.onCollateralWithdraw(msg.sender, amount), "beforeCollateralWithdraw");
        require(token.balanceOf(address(this)) - amount >= MINIMUM_BALANCE, "minimumBalance");
        uint shares = amount * sharesSupply / token.balanceOf(address(this));
        require(shares > 0, "zeroShares");
        sharesSupply -= shares;
        sharesOf[msg.sender] -= shares;
        token.transfer(msg.sender, amount);
    }

    function getCollateralOf(address account) public view returns (uint256) {
        if(sharesSupply == 0) return 0;
        uint256 timeElapsed = block.timestamp - lastAccrued;
        (uint feeBps,) = core.getCollateralFeeBps(address(token));
        uint256 fee = token.balanceOf(address(this)) * feeBps * timeElapsed / 10000 / 365 days;
        if(fee > token.balanceOf(address(this))) return 0;
        return (token.balanceOf(address(this)) - fee) * sharesOf[account] / sharesSupply;
    }

    function seize(address account, uint256 amount) public {
        require(msg.sender == address(core), "onlyCore");
        require(token.balanceOf(address(this)) - amount >= MINIMUM_BALANCE, "minimumBalance");
        accrueFee();
        uint shares = amount * sharesSupply / token.balanceOf(address(this));
        require(shares > 0, "zeroShares");
        sharesSupply -= shares;
        sharesOf[account] -= shares;
        token.transfer(msg.sender, amount);
    }
    
}
