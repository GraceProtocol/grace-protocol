// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function mint(address recipient, uint amount) external;
}

contract RecurringBond {

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint constant MANTISSA = 1e18;
    IERC20 public immutable underlying;
    IERC20 public immutable reward;
    address public operator;
    uint public rewardBudget;
    uint public immutable startTimestamp;
    uint public immutable bondDuration;
    uint public immutable auctionDuration;
    uint public lastUpdateCycle;
    uint public rewardIndexMantissa;
    uint public totalSupply;

    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint) public accountIndexMantissa;
    mapping (address => uint) public accruedRewards;

    constructor(
        IERC20 _underlying,
        IERC20 _reward,
        string memory _name,
        string memory _symbol,
        address _operator,
        uint _rewardBudget,
        uint _startTimestamp,
        uint _bondDuration,
        uint _auctionDuration
    ) {
        require(_startTimestamp > block.timestamp, "startTimestamp must be in the future");
        require(_auctionDuration > 0, "auctionDuration must be greater than 0");
        require(_bondDuration > _auctionDuration, "bondDuration must be greater than auctionDuration");
        require(_rewardBudget > 0, "rewardBudget must be greater than 0");
        underlying = _underlying;
        reward = _reward;
        name = _name;
        symbol = _symbol;
        operator = _operator;
        rewardBudget = _rewardBudget;
        startTimestamp = _startTimestamp;
        bondDuration = _bondDuration;
        auctionDuration = _auctionDuration;
    }

    function updateIndex(address user) internal {
        uint deltaCycles = getCycle() - lastUpdateCycle;
        if(deltaCycles > 0 && !isAuctionActive()) {
            if(totalSupply > 0) {
                uint rewardsAccrued = deltaCycles * rewardBudget * MANTISSA;
                rewardIndexMantissa += rewardsAccrued / totalSupply;
            }
            lastUpdateCycle = getCycle();
        }

        uint deltaIndex = rewardIndexMantissa - accountIndexMantissa[user];
        uint bal = balanceOf[user];
        uint accountDelta = bal * deltaIndex;
        accountIndexMantissa[user] = rewardIndexMantissa;
        accruedRewards[user] += accountDelta / MANTISSA;
    }

    function getCycle() public view returns (uint) {
        if (block.timestamp < startTimestamp) return 0;
        return (block.timestamp - startTimestamp) / bondDuration;
    }

    function isAuctionActive() public view returns (bool) {
        if (block.timestamp < startTimestamp) return false;
        uint currentCycle = getCycle();
        uint currentCycleStart = startTimestamp + (currentCycle * bondDuration);
        uint auctionEnd = currentCycleStart + auctionDuration;
        return block.timestamp < auctionEnd;
    }

    function deposit(uint amount) external {
        updateIndex(msg.sender);
        require(isAuctionActive(), "auction is not active");
        balanceOf[msg.sender] += amount;
        totalSupply += amount;
        underlying.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint amount) external {
        updateIndex(msg.sender);
        require(isAuctionActive(), "auction is not active");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        underlying.transfer(msg.sender, amount);
    }

    function claimable(address user) public view returns(uint) {
        uint deltaCycles = getCycle() - lastUpdateCycle;
        uint rewardsAccrued; // = deltaT * rewardRate * mantissa;
        if(deltaCycles > 0 && !isAuctionActive()) {
            rewardsAccrued = deltaCycles * rewardBudget * MANTISSA;
        }
        uint _rewardIndexMantissa = totalSupply > 0 ? rewardIndexMantissa + (rewardsAccrued / totalSupply) : rewardIndexMantissa;
        uint deltaIndex = _rewardIndexMantissa - accountIndexMantissa[user];
        uint bal = balanceOf[user];
        uint accountDelta = bal * deltaIndex / MANTISSA;
        return (accruedRewards[user] + accountDelta);
    }

    function claim() external {
        updateIndex(msg.sender);
        uint amount = accruedRewards[msg.sender];
        accruedRewards[msg.sender] = 0;
        reward.mint(msg.sender, amount);
    }

    function getNextMaturity() external view returns (uint) {
        if (block.timestamp < startTimestamp) return startTimestamp + bondDuration;
        uint currentCycle = getCycle();
        uint currentCycleStart = startTimestamp + (currentCycle * bondDuration);
        uint currentCycleEnd = currentCycleStart + bondDuration;
        return currentCycleEnd;
    }

    function getNextAuctionEnd() external view returns (uint) {
        if (block.timestamp < startTimestamp) return startTimestamp + auctionDuration;
        uint currentCycle = getCycle();
        if(isAuctionActive()) {
            uint currentCycleStart = startTimestamp + (currentCycle * bondDuration);
            uint auctionEnd = currentCycleStart + auctionDuration;
            return auctionEnd;
        } else {
            uint nextCycleStart = startTimestamp + ((currentCycle + 1) * bondDuration);
            return nextCycleStart + auctionDuration;
        }
    }

    function getCurrentBondYield(uint amount) external view returns (uint) {
        if (totalSupply == 0) return rewardBudget;
        return rewardBudget * amount / totalSupply;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        updateIndex(msg.sender);
        updateIndex(recipient);
        require(recipient != address(0), "ERC20: transfer to the zero address");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
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
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function setBudget(uint _rewardBudget) external {
        updateIndex(msg.sender);
        require(msg.sender == operator, "only operator");
        require(!isAuctionActive(), "auction is active");
        rewardBudget = _rewardBudget;
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "only operator");
        operator = _operator;
    }

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

}