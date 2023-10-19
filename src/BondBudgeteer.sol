// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.21;

interface IGrace {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IFactory {
    function setBudget(address bond, uint budget) external;
    function isBond(address bond) external view returns (bool);
    function allBondsLength() external view returns (uint);
    function allBonds(uint) external view returns (address);
}

interface IBond {
    function bondDuration() external view returns (uint);
    function getNextMaturity() external view returns (uint);
    function isAuctionActive() external view returns (bool);
}

contract BondBudgeteer {

    struct Vote {
        uint unlockTimestamp;
        uint amount;
    }

    address public operator;
    IGrace public immutable GRACE;
    IFactory public immutable FACTORY;
    uint public maxAnnualInflationBps = 1000; // 10% per year
    mapping (address => uint) public bondsVotes;
    mapping (address => mapping (address => Vote)) public usersBondsVotes;

    constructor(address _operator, IGrace _grace, IFactory _factory) {
        operator = _operator;
        GRACE = _grace;
        FACTORY = _factory;
    }

    modifier onlyOperator {
        require(msg.sender == operator, "onlyOperator");
        _;
    }

    function setOperator(address _operator) external onlyOperator { operator = _operator; }
    function setMaxAnnualInflationBps(uint _maxAnnualInflationBps, bool updateAllBonds) external onlyOperator {
        maxAnnualInflationBps = _maxAnnualInflationBps;
        if(updateAllBonds) {
            for(uint i = 0; i < FACTORY.allBondsLength(); i++) {
                updateBudget(FACTORY.allBonds(i));
            }
        }
    }

    function voteForBond(address bond, uint amount) external {
        require(FACTORY.isBond(bond), "notBond");
        bondsVotes[bond] += amount;
        usersBondsVotes[msg.sender][bond].amount += amount;
        if(IBond(bond).isAuctionActive()) {
            usersBondsVotes[msg.sender][bond].unlockTimestamp = IBond(bond).getNextMaturity();
        } else {
            usersBondsVotes[msg.sender][bond].unlockTimestamp = IBond(bond).getNextMaturity() + IBond(bond).bondDuration();
        }
        usersBondsVotes[msg.sender][bond].unlockTimestamp = IBond(bond).getNextMaturity();
        uint totalVotes = bondsVotes[bond];
        uint yearlyBudget = totalVotes * maxAnnualInflationBps / 10000;
        uint bondDuration = IBond(bond).bondDuration();
        uint budget = yearlyBudget * bondDuration / 365 days;
        FACTORY.setBudget(bond, budget);
        GRACE.transferFrom(msg.sender, address(this), amount);
    }

    function unvoteForBond(address bond, uint amount) external {
        require(FACTORY.isBond(bond), "notBond");
        require(usersBondsVotes[msg.sender][bond].unlockTimestamp < block.timestamp, "notUnlocked");
        bondsVotes[bond] -= amount;
        usersBondsVotes[msg.sender][bond].amount -= amount;
        uint totalVotes = bondsVotes[bond];
        uint yearlyBudget = totalVotes * maxAnnualInflationBps / 10000;
        uint bondDuration = IBond(bond).bondDuration();
        uint budget = yearlyBudget * bondDuration / 365 days;
        FACTORY.setBudget(bond, budget);
        GRACE.transfer(msg.sender, amount);
    }

    function updateBudget(address bond) public {
        require(FACTORY.isBond(bond), "notBond");
        uint totalVotes = bondsVotes[bond];
        uint yearlyBudget = totalVotes * maxAnnualInflationBps / 10000;
        uint bondDuration = IBond(bond).bondDuration();
        uint budget = yearlyBudget * bondDuration / 365 days;
        FACTORY.setBudget(bond, budget);
    }

}