// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import "./RecurringBond.sol";

interface IGrace {
    function mint(address recipient, uint amount) external;
}

contract BondFactory {

    IGrace public immutable GRACE;
    address public operator;
    mapping (address => bool) public isBond;
    address[] public allBonds;

    constructor (address _grace) {
        GRACE = IGrace(_grace);
        operator = msg.sender;
    }

    function allBondsLength() external view returns (uint) {
        return allBonds.length;
    }

    function createBond(
        address asset,
        string memory name,
        string memory symbol,
        uint startTimestamp,
        uint bondDuration,
        uint auctionDuration,
        uint initialRewardBudget
    ) external returns (address bond) {
        require(msg.sender == operator, "onlyOperator");
        bond = address(new RecurringBond(
            IERC20(asset),
            IERC20(address(GRACE)),
            name,
            symbol,
            startTimestamp,
            bondDuration,
            auctionDuration,
            initialRewardBudget
        ));
        isBond[bond] = true;
        allBonds.push(bond);
        emit BondCreated(bond);
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "onlyOperator");
        operator = _operator;
    }

    function transferReward(address recipient, uint amount) external {
        require(isBond[msg.sender], "onlyBond");
        GRACE.mint(recipient, amount);
    }

    function setBudget(address bond, uint budget) external {
        require(msg.sender == operator, "onlyOperator");
        require(isBond[bond], "onlyBond");
        RecurringBond(bond).setBudget(budget);
    }

    event BondCreated(address bond);

}