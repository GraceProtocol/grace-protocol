// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFactory {
    function transferReward(address recipient, uint amount) external;
}

interface IPool is IERC20 {
    function asset() external view returns (address);
    function deposit(uint256 assets) external returns (uint256 shares);
    function withdraw(uint256 assets) external returns (uint256 shares);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}

contract Vault {

    using SafeERC20 for IERC20;
    uint constant MANTISSA = 1e18;
    IPool public immutable pool;
    IERC20 public immutable asset;
    bool public immutable isWETH;
    IFactory public factory;
    uint public rewardBudget;
    uint public lastUpdate;
    uint public rewardIndexMantissa;
    uint public totalSupply;
    bytes32 public immutable DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public balanceOf;
    mapping(address => uint) public nonces;    
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint) public accountIndexMantissa;
    mapping (address => uint) public accruedRewards;

    constructor(
        address _pool,
        uint _initialRewardBudget,
        bool _isWETH
    ) {
        pool = IPool(_pool);
        asset = IERC20(IPool(_pool).asset());
        factory = IFactory(msg.sender);
        rewardBudget = _initialRewardBudget;
        isWETH = _isWETH;
        asset.approve(_pool, type(uint256).max);
    }

    modifier onlyWETH() {
        require(isWETH, "onlyWETH");
        _;
    }

    receive() external payable {}

    function updateIndex(address user) internal {
        uint deltaT = block.timestamp - lastUpdate;
        if(deltaT > 0) {
            if(rewardBudget > 0 && totalSupply > 0) {
                uint rewardsAccrued = deltaT * rewardBudget * MANTISSA / 365 days;
                rewardIndexMantissa += rewardsAccrued / totalSupply;
            }
            lastUpdate = block.timestamp;
        }

        uint deltaIndex = rewardIndexMantissa - accountIndexMantissa[user];
        uint bal = balanceOf[user];
        uint accountDelta = bal * deltaIndex;
        accountIndexMantissa[user] = rewardIndexMantissa;
        accruedRewards[user] += accountDelta / MANTISSA;
    }

    function reapprove() external {
        asset.approve(address(pool), type(uint256).max);
    }

    function depositShares(uint amount, address recipient) public {
        updateIndex(recipient);
        balanceOf[recipient] += amount;
        totalSupply += amount;
        pool.transferFrom(msg.sender, address(this), amount);
    }

    function depositShares(uint amount) external {
        depositShares(amount, msg.sender);
    }

    function depositAsset(uint amount, address recipient) public {
        updateIndex(recipient);
        asset.safeTransferFrom(msg.sender, address(this), amount);
        uint shares = pool.deposit(amount);
        balanceOf[recipient] += shares;
        totalSupply += shares;
    }

    function depositAsset(uint amount) external {
        depositAsset(amount, msg.sender);
    }

    function depositETH(address recipient) public payable onlyWETH {
        updateIndex(recipient);
        IWETH(address(asset)).deposit{value: msg.value}();
        uint shares = pool.deposit(msg.value);
        balanceOf[recipient] += shares;
        totalSupply += shares;
    }

    function depositETH() external payable onlyWETH {
        depositETH(msg.sender);
    }

    function withdrawETH(uint amount, address payable recipient, address owner) public onlyWETH {
        updateIndex(owner);
        uint shares = pool.withdraw(amount);
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        balanceOf[owner] -= shares;
        totalSupply -= shares;
        IWETH(address(asset)).withdraw(amount);
        recipient.transfer(amount);
    }

    function withdrawETH(uint amount) external onlyWETH {
        withdrawETH(amount, payable(msg.sender), msg.sender);
    }

    function withdrawShares(uint amount, address recipient, address owner) public {
        updateIndex(owner);
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - amount;
        }
        balanceOf[owner] -= amount;
        totalSupply -= amount;
        pool.transfer(recipient, amount);
    }

    function withdrawShares(uint amount) external {
        withdrawShares(amount, msg.sender, msg.sender);
    }

    function withdrawAsset(uint amount, address recipient, address owner) public {
        updateIndex(owner);
        uint shares = pool.withdraw(amount);
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        balanceOf[owner] -= shares;
        totalSupply -= shares;
        asset.safeTransfer(recipient, amount);
    }

    function withdrawAsset(uint amount) external {
        withdrawAsset(amount, msg.sender, msg.sender);
    }

    function claimable(address user) public view returns(uint) {
        uint deltaT = block.timestamp - lastUpdate;
        uint rewardsAccrued = deltaT * rewardBudget * MANTISSA / 365 days;
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
        factory.transferReward(msg.sender, amount);
        emit Claim(msg.sender, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function setBudget(uint _rewardBudget) external {
        updateIndex(msg.sender);
        require(msg.sender == address(factory), "only factory");
        rewardBudget = _rewardBudget;
        emit SetBudget(_rewardBudget);
    }

    event Approval(address indexed owner, address indexed spender, uint value);
    event Deposit(address indexed caller, address indexed owner, uint amount);
    event Withdraw(address indexed caller, address indexed recipient, address indexed owner, uint amount);
    event Claim(address indexed owner, uint amount);
    event SetBudget(uint rewardBudget);
}