// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.21;

import "./RecurringBond.sol";

interface IGrace {
    function balanceOf(address account) external view returns (uint256);
    function mint(address recipient, uint amount) external;
}

contract BondFactory {

    IGrace public immutable GRACE;
    address public operator;
    address public budgeteer;
    mapping (address => bool) public isBond;
    address[] public allBonds;

    constructor (IGrace _grace, address _operator) {
        GRACE = _grace;
        operator = _operator;
    }

    function createBond(
        IERC20 underlying,
        string memory name,
        string memory symbol,
        uint startTimestamp,
        uint bondDuration,
        uint auctionDuration
    ) external returns (address bond) {
        require(msg.sender == operator, "onlyOperator");
        bond = address(new RecurringBond(
            underlying,
            IERC20(address(GRACE)),
            name,
            symbol,
            startTimestamp,
            bondDuration,
            auctionDuration
        ));
        isBond[bond] = true;
        allBonds.push(bond);
        emit BondCreated(bond);
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "onlyOperator");
        operator = _operator;
    }

    function setBudgeteer(address _budgeteer) external {
        require(msg.sender == operator, "onlyOperator");
        budgeteer = _budgeteer;
    }

    function transferReward(address recipient, uint amount) external {
        require(isBond[msg.sender], "onlyBond");
        GRACE.mint(recipient, amount);
    }

    function setBudget(address bond, uint budget) external {
        require(msg.sender == budgeteer, "onlyBudgeteer");
        RecurringBond(bond).setBudget(budget);
    }

    event BondCreated(address bond);

}