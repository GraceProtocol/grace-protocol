// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import "./Vault.sol";

interface IGTR {
    function mint(address recipient, uint amount) external;
}

contract VaultFactory {

    uint constant MANTISSA = 1e18;
    IGTR public immutable gtr;
    address public immutable weth;
    address public operator;
    uint public rewardBudget;
    uint public lastUpdate;
    uint public totalSupply;
    uint public rewardIndexMantissa;
    mapping (address => bool) public isVault;
    mapping(address => uint) public balanceOf;
    mapping (address => uint) public vaultIndexMantissa;
    mapping (address => uint) public accruedRewards;
    address[] public allVaults;

    constructor (address _gtr, address _weth, uint _initialRewardBudget) {
        gtr = IGTR(_gtr);
        weth = _weth;
        operator = msg.sender;
        rewardBudget = _initialRewardBudget;
    }

    function allVaultsLength() external view returns (uint) {
        return allVaults.length;
    }

    function updateIndex(address vault) internal {
        uint deltaT = block.timestamp - lastUpdate;
        if(deltaT > 0) {
            if(rewardBudget > 0 && totalSupply > 0) {
                uint rewardsAccrued = deltaT * rewardBudget * MANTISSA / 365 days;
                rewardIndexMantissa += rewardsAccrued / totalSupply;
            }
            lastUpdate = block.timestamp;
        }

        uint deltaIndex = rewardIndexMantissa - vaultIndexMantissa[vault];
        uint bal = balanceOf[vault];
        uint vaultDelta = bal * deltaIndex;
        vaultIndexMantissa[vault] = rewardIndexMantissa;
        accruedRewards[vault] += vaultDelta / MANTISSA;
    }

    function createVault(
        address pool,
        uint initialWeight
    ) external returns (address vault) {
        require(msg.sender == operator, "onlyOperator");
        bool isWETH = IPool(pool).asset() == weth;
        vault = address(new Vault(
            address(pool),
            isWETH,
            address(gtr)
        ));
        updateIndex(vault);
        isVault[vault] = true;
        balanceOf[vault] = initialWeight;
        totalSupply += initialWeight;
        allVaults.push(vault);
        emit VaultCreated(vault);
        emit WeightUpdated(vault, initialWeight);
    }

    function setWeight(address vault, uint weight) external {
        require(msg.sender == operator, "onlyOperator");
        require(isVault[vault], "notVault");
        updateIndex(vault);
        totalSupply = totalSupply - balanceOf[vault] + weight;
        balanceOf[vault] = weight;
        emit WeightUpdated(vault, weight);
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "onlyOperator");
        operator = _operator;
    }

    function claim() external returns (uint) {
        updateIndex(msg.sender);
        uint amount = accruedRewards[msg.sender];
        accruedRewards[msg.sender] = 0;
        gtr.mint(msg.sender, amount);
        emit Claim(msg.sender, amount);
        return amount;
    }

    function claimable(address vault) public view returns(uint) {
        uint deltaT = block.timestamp - lastUpdate;
        uint rewardsAccrued = deltaT * rewardBudget * MANTISSA / 365 days;
        uint _rewardIndexMantissa = totalSupply > 0 ? rewardIndexMantissa + (rewardsAccrued / totalSupply) : rewardIndexMantissa;
        uint deltaIndex = _rewardIndexMantissa - vaultIndexMantissa[vault];
        uint bal = balanceOf[vault];
        uint vaultDelta = bal * deltaIndex / MANTISSA;
        return (accruedRewards[vault] + vaultDelta);
    }

    function setBudget(uint _rewardBudget) external {
        require(msg.sender == operator, "onlyOperator");
        updateIndex(address(0));
        rewardBudget = _rewardBudget;
    }

    function getVaultBudget(address vault) external view returns (uint) {
        return rewardBudget * balanceOf[vault] / totalSupply;
    }

    event VaultCreated(address vault);
    event WeightUpdated(address vault, uint weight);
    event Claim(address vault, uint amount);

}