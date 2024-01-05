// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

contract BorrowController {

    uint constant MANTISSA = 1e18;
    address public owner;
    address public guardian;
    uint public dailyBorrowLimitUsd = 100000e18; // $100,000
    bool public forbidContracts = true;
    mapping(address => uint) public dailyBorrowLimitLastUpdate;
    mapping(address => uint) public lastDailyBorrowLimitRemainingUsd;
    mapping(address => bool) public isPoolBorrowPaused;
    mapping(address => bool) public isPoolBorrowSuspended;
    mapping(address => bool) public isContractAllowed;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    modifier onlyGuardian {
        require(msg.sender == guardian, "onlyGuardian");
        _;
    }

    function setOwner(address _owner) external onlyOwner { owner = _owner; }
    function setGuardian(address _guardian) external onlyOwner { guardian = _guardian; }
    function setPoolBorrowPaused(address pool, bool paused) external onlyGuardian {
        require(!isPoolBorrowSuspended[pool], "borrowSuspended");
        isPoolBorrowPaused[pool] = paused;
    }
    function setForbidContracts(bool forbid) external onlyOwner { forbidContracts = forbid; }
    function setContractAllowed(address contractAddress, bool allowed) external onlyOwner { isContractAllowed[contractAddress] = allowed; }
    function setPoolBorrowSuspended(address pool, bool suspended) external onlyOwner {
        isPoolBorrowSuspended[pool] = suspended;
        if(suspended) isPoolBorrowPaused[pool] = true;
    }
    function setDailyBorrowLimitUsd(uint _dailyBorrowLimitUsd) public onlyOwner {
        dailyBorrowLimitUsd = _dailyBorrowLimitUsd;
    }

    function updateDailyBorrowLimit() internal {
        uint timeElapsed = block.timestamp - dailyBorrowLimitLastUpdate[msg.sender];
        if(timeElapsed == 0) return;
        uint addedCapacity = timeElapsed * dailyBorrowLimitUsd / 1 days;
        uint newLimit = lastDailyBorrowLimitRemainingUsd[msg.sender] + addedCapacity;
        if(newLimit > dailyBorrowLimitUsd) newLimit = dailyBorrowLimitUsd;
        lastDailyBorrowLimitRemainingUsd[msg.sender] = newLimit;
        dailyBorrowLimitLastUpdate[msg.sender] = block.timestamp;
    }

    function onBorrow(address pool, address borrower, uint amount, uint price) external {
        require(!isPoolBorrowPaused[pool], "borrowPaused");
        if(forbidContracts) {
            require(tx.origin == borrower || isContractAllowed[borrower], "contractNotAllowed");
        }
        updateDailyBorrowLimit();
        uint extraDebtUsd = amount * price / MANTISSA;
        lastDailyBorrowLimitRemainingUsd[msg.sender] -= extraDebtUsd;
    }

    function onRepay(address /*pool*/, address /*borrower*/, uint amount, uint price) external {
        updateDailyBorrowLimit();
        uint repaidDebtUsd = amount * price / MANTISSA;
        if(lastDailyBorrowLimitRemainingUsd[msg.sender] + repaidDebtUsd > dailyBorrowLimitUsd) {
            lastDailyBorrowLimitRemainingUsd[msg.sender] = dailyBorrowLimitUsd;
        } else {
            lastDailyBorrowLimitRemainingUsd[msg.sender] += repaidDebtUsd;
        }
    }

}