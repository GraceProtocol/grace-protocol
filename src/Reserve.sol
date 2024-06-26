// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGTR is IERC20 {
    function burn(uint256 amount) external returns (bool);
}

contract Reserve {

    using SafeERC20 for IERC20;

    struct AllowanceRequest {
        uint timestamp;
        uint256[] amounts;
        IERC20[] tokens;
        address dst;
    }

    IGTR public immutable gtr;
    address public owner;
    uint constant MANTISSA = 1e18;
    uint public locked = 1; // 1 = unlocked, 2 = locked
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));
    AllowanceRequest allowanceRequest;

    constructor(address _gtr) {
        gtr = IGTR(_gtr);
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    function setOwner(address _owner) external onlyOwner { owner = _owner; }

    function requestAllowance(IERC20[] calldata tokens, uint256[] calldata amounts, address dst) external onlyOwner {
        require(tokens.length == amounts.length, "lengthMismatch");
        allowanceRequest = AllowanceRequest(block.timestamp, amounts, tokens, dst);
        emit AllowanceRequested(amounts, tokens, dst);
    }

    function executeAllowance() external onlyOwner {
        require(locked == 1, "locked");
        locked = 2;
        AllowanceRequest memory request = allowanceRequest;
        require(block.timestamp > request.timestamp + 14 days, "tooSoon");
        require(block.timestamp < request.timestamp + 60 days, "tooLate");
        allowanceRequest = AllowanceRequest(0, new uint256[](0), new IERC20[](0), address(0));
        for(uint i = 0; i < request.tokens.length; i++) {
            uint bal = request.tokens[i].balanceOf(address(this));
            uint amount = request.amounts[i] > bal ? bal : request.amounts[i];
            request.tokens[i].forceApprove(request.dst, amount);
        }
        locked = 1;
        emit AllowanceExecuted(request.amounts, request.tokens, request.dst);
    }

    function getAllowanceRequestTimestamp() external view returns (uint) { return allowanceRequest.timestamp; }
    function getAllowanceRequestDst() external view returns (address) { return allowanceRequest.dst; }
    function getAllowanceRequestTokensLength() external view returns (uint) { return allowanceRequest.tokens.length; }
    function getAllowanceRequestTokens(uint i) external view returns (address, uint) {
        return (
            address(allowanceRequest.tokens[i]),
            allowanceRequest.amounts[i]
        );
    }

    function rageQuit(uint256 gtrAmount, IERC20[] memory tokens) external {
        require(locked == 1, "locked");
        locked = 2;
        require(tokens.length > 0, "noTokens");
        gtr.transferFrom(msg.sender, address(this), gtrAmount);
        uint totalSupply = gtr.totalSupply();
        gtr.burn(gtrAmount);
        // calculate the user's share of the GTR supply
        uint shareMantissa = gtrAmount * MANTISSA / totalSupply;
        for(uint i = 0; i < tokens.length; i++) {
            // check for duplicate tokens
            for(uint j = i + 1; j < tokens.length; j++) {
                require(tokens[i] != tokens[j], "duplicate token");
            }
            uint balance = tokens[i].balanceOf(address(this));
            require(balance > 0, "zeroBalance");
            // calculate the user's share of the token balance
            uint out = balance * shareMantissa / MANTISSA;
            tokens[i].safeTransfer(msg.sender, out);
        }
        emit RageQuit(msg.sender, gtrAmount, tokens);
        locked = 1;
    }

    event RageQuit(address indexed sender, uint256 gtrAmount, IERC20[] tokens);
    event AllowanceRequested(uint256[] amounts, IERC20[] tokens, address dst);
    event AllowanceExecuted(uint256[] amounts, IERC20[] tokens, address dst);
}