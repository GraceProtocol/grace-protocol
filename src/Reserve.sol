// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGrace is IERC20 {
    function burn(uint256 amount) external returns (bool);
}

contract Reserve {

    using SafeERC20 for IERC20;

    struct PullRequest {
        uint timestamp;
        uint256[] amounts;
        IERC20[] tokens;
        address dst;
    }

    IGrace public immutable grace;
    address public owner;
    uint constant MANTISSA = 1e18;
    uint public locked = 1; // 1 = unlocked, 2 = locked
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));
    PullRequest pullRequest;

    constructor(address _grace, address _owner) {
        grace = IGrace(_grace);
        owner = _owner;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    function setOwner(address _owner) external onlyOwner { owner = _owner; }

    function requestPull(IERC20[] calldata tokens, uint256[] calldata amounts, address dst) external onlyOwner {
        require(tokens.length == amounts.length, "lengthMismatch");
        pullRequest = PullRequest(block.timestamp, amounts, tokens, dst);
        emit PullRequested(amounts, tokens, dst);
    }

    function executePull() external onlyOwner {
        require(locked == 1, "locked");
        locked = 2;
        PullRequest memory request = pullRequest;
        require(block.timestamp > request.timestamp + 60 days, "tooSoon");
        require(block.timestamp < request.timestamp + 90 days, "tooLate");
        pullRequest = PullRequest(0, new uint256[](0), new IERC20[](0), address(0));
        for(uint i = 0; i < request.tokens.length; i++) {
            uint bal = request.tokens[i].balanceOf(address(this));
            uint amount = request.amounts[i] > bal ? bal : request.amounts[i];
            request.tokens[i].safeTransfer(request.dst, amount);
        }
        locked = 1;
        emit PullExecuted(request.amounts, request.tokens, request.dst);
    }

    function getPullRequestTimestamp() external view returns (uint) { return pullRequest.timestamp; }
    function getPullRequestDst() external view returns (address) { return pullRequest.dst; }
    function getPullRequestTokensLength() external view returns (uint) { return pullRequest.tokens.length; }
    function getPullRequestTokens(uint i) external view returns (address, uint) {
        return (
            address(pullRequest.tokens[i]),
            pullRequest.amounts[i]
        );
    }

    function rageQuit(uint256 graceAmount, IERC20[] memory tokens) external {
        require(locked == 1, "locked");
        locked = 2;
        require(tokens.length > 0, "noTokens");
        uint256 dayOfMonth = (block.timestamp / 1 days) % 30;
        require(dayOfMonth == 0, "Only first day of each month");
        grace.transferFrom(msg.sender, address(this), graceAmount);
        uint totalSupply = grace.totalSupply();
        grace.burn(graceAmount);
        uint shareMantissa = graceAmount * MANTISSA / totalSupply;
        for(uint i = 0; i < tokens.length; i++) {
            for(uint j = i + 1; j < tokens.length; j++) {
                require(tokens[i] != tokens[j], "duplicate token");
            }
            uint balance = tokens[i].balanceOf(address(this));
            require(balance > 0, "zeroBalance");
            uint out = balance * shareMantissa / MANTISSA;
            tokens[i].safeTransfer(msg.sender, out);
        }
        emit RageQuit(msg.sender, graceAmount);
        locked = 1;
    }

    event RageQuit(address indexed sender, uint256 graceAmount);
    event PullRequested(uint256[] amounts, IERC20[] tokens, address dst);
    event PullExecuted(uint256[] amounts, IERC20[] tokens, address dst);
}