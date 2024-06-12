// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFactory {
    function claim() external returns (uint);
    function claimable(address vault) external view returns(uint);
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
    IERC20 public immutable gtr;
    bool public immutable isWETH;
    IFactory public factory;
    uint public lastUpdate;
    uint public rewardIndexMantissa;
    uint public totalSupply;
    uint256 private locked = 1;
    bytes32 public immutable DOMAIN_SEPARATOR;
    mapping(address => uint) public balanceOf;
    mapping(address => uint) public nonces;    
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint) public accountIndexMantissa;
    mapping (address => uint) public accruedRewards;

    constructor(
        address _pool,
        bool _isWETH,
        address _gtr
    ) {
        pool = IPool(_pool);
        asset = IERC20(IPool(_pool).asset());
        factory = IFactory(msg.sender);
        isWETH = _isWETH;
        gtr = IERC20(_gtr);
        asset.approve(_pool, type(uint256).max);
    }

    modifier onlyWETH() {
        require(isWETH, "onlyWETH");
        _;
    }

    modifier nonReentrant() virtual {
        require(locked == 1, "REENTRANCY");

        locked = 2;

        _;

        locked = 1;
    }

    receive() external payable {}

    function updateIndex(address user) internal {
        uint deltaT = block.timestamp - lastUpdate;
        // if deltaT is 0, no need to update
        if(deltaT > 0) {
            // if totalSupply is 0, skip but update lastUpdate
            if(totalSupply > 0) {
                uint rewardsAccrued = factory.claim();
                rewardIndexMantissa += rewardsAccrued * MANTISSA / totalSupply;
            }
            lastUpdate = block.timestamp;
        }

        // accrue rewards for user
        uint deltaIndex = rewardIndexMantissa - accountIndexMantissa[user];
        uint bal = balanceOf[user];
        uint accountDelta = bal * deltaIndex;
        accountIndexMantissa[user] = rewardIndexMantissa;
        // divide by MANTISSA because rewardIndexMantissa is scaled by MANTISSA
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
        emit Deposit(msg.sender, recipient, amount);
    }

    function depositShares(uint amount) external {
        depositShares(amount, msg.sender);
    }

    function depositAsset(uint amount, address recipient) public nonReentrant {
        updateIndex(recipient);
        asset.safeTransferFrom(msg.sender, address(this), amount);
        uint shares = pool.deposit(amount);
        balanceOf[recipient] += shares;
        totalSupply += shares;
        emit Deposit(msg.sender, recipient, shares);
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
        emit Deposit(msg.sender, recipient, shares);
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
        emit Withdraw(msg.sender, recipient, owner, shares);
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed.");
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
        emit Withdraw(msg.sender, recipient, owner, amount);
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
        emit Withdraw(msg.sender, recipient, owner, shares);
    }

    function withdrawAsset(uint amount) external {
        withdrawAsset(amount, msg.sender, msg.sender);
    }

    function claimable(address user) public view returns(uint) {
        uint rewardsAccrued = factory.claimable(address(this));
        uint _rewardIndexMantissa = totalSupply > 0 ? rewardIndexMantissa + (rewardsAccrued * MANTISSA / totalSupply) : rewardIndexMantissa;
        uint deltaIndex = _rewardIndexMantissa - accountIndexMantissa[user];
        uint bal = balanceOf[user];
        uint accountDelta = bal * deltaIndex / MANTISSA;
        return (accruedRewards[user] + accountDelta);
    }

    function claim(address user) external {
        updateIndex(user);
        uint amount = accruedRewards[user];
        accruedRewards[user] = 0;
        gtr.transfer(user, amount);
        emit Claim(user, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    event Approval(address indexed owner, address indexed spender, uint value);
    event Deposit(address indexed caller, address indexed owner, uint amount);
    event Withdraw(address indexed caller, address indexed recipient, address indexed owner, uint amount);
    event Claim(address indexed owner, uint amount);
}