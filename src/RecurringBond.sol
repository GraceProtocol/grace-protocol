// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IFactory {
    function transferReward(address recipient, uint amount) external;
}

contract RecurringBond {

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint constant MANTISSA = 1e18;
    IERC20 public immutable underlying;
    IERC20 public immutable reward;
    IFactory public factory;
    uint public rewardBudget;
    uint public nextRewardBudget;
    uint public immutable startTimestamp;
    uint public immutable bondDuration;
    uint public immutable auctionDuration;
    uint public lastUpdateCycle;
    uint public rewardIndexMantissa;
    uint public deposits;

    mapping (address => uint) public balances;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint) public accountIndexMantissa;
    mapping (address => uint) public accruedRewards;
    mapping (address => mapping(uint => uint)) public accountCyclePreorder;
    mapping (uint => uint) public cyclePreorders;

    constructor(
        IERC20 _underlying,
        IERC20 _reward,
        string memory _name,
        string memory _symbol,
        uint _startTimestamp,
        uint _bondDuration,
        uint _auctionDuration,
        uint _initialRewardBudget
    ) {
        require(_startTimestamp >= block.timestamp, "startTimestamp must be now or in the future");
        require(_auctionDuration > 0, "auctionDuration must be greater than 0");
        require(_bondDuration > _auctionDuration, "bondDuration must be greater than auctionDuration");
        underlying = _underlying;
        reward = _reward;
        name = _name;
        symbol = _symbol;
        factory = IFactory(msg.sender);
        startTimestamp = _startTimestamp;
        bondDuration = _bondDuration;
        auctionDuration = _auctionDuration;
        rewardBudget = _initialRewardBudget;
        nextRewardBudget = _initialRewardBudget;
    }

    function totalSupply() public view returns (uint) {
        return deposits - cyclePreorders[getCycle()];
    }

    function balanceOf(address user) public view returns (uint) {
        return balances[user] - accountCyclePreorder[user][getCycle()];
    }

    function updateIndex(address user) internal {
        uint deltaCycles = getCycle() - lastUpdateCycle;
        if(deltaCycles > 0 && !isAuctionActive()) {
            if(deposits > 0) {
                uint rewardsAccrued = deltaCycles * rewardBudget * MANTISSA;
                rewardIndexMantissa += rewardsAccrued / deposits;
                rewardBudget = nextRewardBudget;
            }
            lastUpdateCycle = getCycle();
        }

        uint deltaIndex = rewardIndexMantissa - accountIndexMantissa[user];
        uint bal = balanceOf(user);
        uint accountDelta = bal * deltaIndex;
        accountIndexMantissa[user] = rewardIndexMantissa;
        accruedRewards[user] += accountDelta / MANTISSA;
    }

    function getCycle() public view returns (uint) {
        if (block.timestamp < startTimestamp) return 0;
        return ((block.timestamp - startTimestamp) / bondDuration) + 1;
    }

    function isAuctionActive() public view returns (bool) {
        if (block.timestamp < startTimestamp) return false;
        uint currentCycle = getCycle();
        uint currentCycleStart = startTimestamp + ((currentCycle - 1) * bondDuration);
        uint auctionEnd = currentCycleStart + auctionDuration;
        return block.timestamp < auctionEnd;
    }

    function deposit(uint amount) external {
        updateIndex(msg.sender);
        require(isAuctionActive(), "auction is not active");
        balances[msg.sender] = balanceOf(msg.sender) + amount;
        deposits += amount;
        underlying.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint amount) external {
        updateIndex(msg.sender);
        require(isAuctionActive(), "auction is not active");
        balances[msg.sender] = balanceOf(msg.sender) - amount;
        deposits -= amount;
        underlying.transfer(msg.sender, amount);
    }

    function totalPreorders() external view returns (uint) {
        uint currentCycle = getCycle();
        return cyclePreorders[currentCycle];
    }

    function preorderOf(address account) external view returns (uint) {
        uint currentCycle = getCycle();
        return accountCyclePreorder[account][currentCycle];
    }

    function preorder(uint amount) external {
        updateIndex(msg.sender);
        require(!isAuctionActive(), "auction is active");
        uint currentCycle = getCycle();
        accountCyclePreorder[msg.sender][currentCycle] += amount;
        cyclePreorders[currentCycle] += amount;
        balances[msg.sender] += amount;
        deposits += amount;
        underlying.transferFrom(msg.sender, address(this), amount);
    }

    function cancelPreorder(uint amount) external {
        updateIndex(msg.sender);
        require(!isAuctionActive(), "auction is active");
        uint currentCycle = getCycle();
        accountCyclePreorder[msg.sender][currentCycle] -= amount;
        cyclePreorders[currentCycle] -= amount;
        balances[msg.sender] -= amount;
        deposits -= amount;
        underlying.transfer(msg.sender, amount);
    }

    function claimable(address user) public view returns(uint) {
        uint deltaCycles = getCycle() - lastUpdateCycle;
        uint rewardsAccrued; // = deltaT * rewardRate * mantissa;
        if(deltaCycles > 0 && !isAuctionActive()) {
            rewardsAccrued = deltaCycles * rewardBudget * MANTISSA;
        }
        uint _rewardIndexMantissa = deposits > 0 ? rewardIndexMantissa + (rewardsAccrued / deposits) : rewardIndexMantissa;
        uint deltaIndex = _rewardIndexMantissa - accountIndexMantissa[user];
        uint bal = balanceOf(user);
        uint accountDelta = bal * deltaIndex / MANTISSA;
        return (accruedRewards[user] + accountDelta);
    }

    function claim() external {
        updateIndex(msg.sender);
        uint amount = accruedRewards[msg.sender];
        accruedRewards[msg.sender] = 0;
        factory.transferReward(msg.sender, amount);
        
    }

    function getNextMaturity() external view returns (uint) {
        if (block.timestamp < startTimestamp) return startTimestamp + bondDuration;
        uint currentCycle = getCycle();
        uint currentCycleStart = startTimestamp + ((currentCycle - 1) * bondDuration);
        uint currentCycleEnd = currentCycleStart + bondDuration;
        return currentCycleEnd;
    }

    function getNextAuctionEnd() external view returns (uint) {
        if (block.timestamp < startTimestamp) return startTimestamp + auctionDuration;
        uint currentCycle = getCycle();
        if(isAuctionActive()) {
            uint currentCycleStart = startTimestamp + ((currentCycle - 1) * bondDuration);
            uint auctionEnd = currentCycleStart + auctionDuration;
            return auctionEnd;
        } else {
            uint nextCycleStart = startTimestamp + ((currentCycle + 1) * bondDuration);
            return nextCycleStart + auctionDuration;
        }
    }

    function getCurrentBondYield(uint amount) external view returns (uint) {
        if (deposits == 0) return rewardBudget;
        return rewardBudget * amount / deposits;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        updateIndex(msg.sender);
        updateIndex(recipient);
        require(recipient != address(0), "ERC20: transfer to the zero address");
        balances[msg.sender] = balanceOf(msg.sender) - amount;
        balances[recipient] = balanceOf(recipient) + amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        require(spender != address(0), "ERC20: approve to the zero address");
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        updateIndex(sender);
        updateIndex(recipient);
        require(recipient != address(0), "ERC20: transfer to the zero address");
        allowance[sender][msg.sender] -= amount;
        balances[sender] = balanceOf(sender) - amount;
        balances[recipient] = balanceOf(recipient) + amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function setBudget(uint _rewardBudget) external {
        updateIndex(msg.sender);
        require(msg.sender == address(factory), "only factory");
        nextRewardBudget = _rewardBudget;
        if (!isAuctionActive()) {
            rewardBudget = _rewardBudget;
        }
    }

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

}