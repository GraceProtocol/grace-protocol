// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import "./StakingPool.sol";

interface IGrace {
    function mint(address recipient, uint amount) external;
}

contract StakingFactory {

    IGrace public immutable GRACE;
    address public operator;
    mapping (address => bool) public isPool;
    address[] public allPools;

    constructor (address _grace) {
        GRACE = IGrace(_grace);
        operator = msg.sender;
    }

    function allPoolsLength() external view returns (uint) {
        return allPools.length;
    }

    function createPool(
        address asset,
        uint initialRewardBudget
    ) external returns (address pool) {
        require(msg.sender == operator, "onlyOperator");
        pool = address(new StakingPool(
            IERC20(asset),
            IERC20(address(GRACE)),
            initialRewardBudget
        ));
        isPool[pool] = true;
        allPools.push(pool);
        emit PoolCreated(pool);
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "onlyOperator");
        operator = _operator;
    }

    function transferReward(address recipient, uint amount) external {
        require(isPool[msg.sender], "onlyPool");
        GRACE.mint(recipient, amount);
    }

    function setBudget(address pool, uint budget) external {
        require(msg.sender == operator, "onlyOperator");
        require(isPool[pool], "onlyPool");
        StakingPool(pool).setBudget(budget);
    }

    event PoolCreated(address pool);

}