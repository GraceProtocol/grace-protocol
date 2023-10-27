// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.21;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function totalSupply() external view returns (uint256);
    function burn(uint256 amount) external returns (bool);
}

contract Reserve {

    struct PullRequest {
        uint timestamp;
        uint256[] amounts;
        IERC20[] tokens;
        address dst;
    }

    IERC20 public immutable grace;
    address public owner;
    uint constant MANTISSA = 1e18;
    uint public locked = 1; // 1 = unlocked, 2 = locked
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));
    PullRequest public pullRequest;

    constructor(IERC20 _grace, address _owner) {
        grace = _grace;
        owner = _owner;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Reserve: TRANSFER_FAILED');
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
        require(block.timestamp > request.timestamp + 30 days, "tooSoon");
        pullRequest = PullRequest(0, new uint256[](0), new IERC20[](0), address(0));
        for(uint i = 0; i < request.tokens.length; i++) {
            _safeTransfer(address(request.tokens[i]), request.dst, request.amounts[i]);
        }
        locked = 1;
        emit PullExecuted(request.amounts, request.tokens, request.dst);
    }

    function rageQuit(uint256 graceAmount, IERC20[] memory tokens) external {
        require(locked == 1, "locked");
        locked = 2;
        uint256 dayOfMonth = (block.timestamp / 1 days) % 30;
        require(dayOfMonth == 1, "Function can only be called on the first day of each month");
        if(graceAmount == type(uint256).max) graceAmount = grace.balanceOf(msg.sender);
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
            uint share = balance * shareMantissa / MANTISSA;
            _safeTransfer(address(tokens[i]), msg.sender, share);
        }
        emit RageQuit(msg.sender, graceAmount);
        locked = 1;
    }

    event RageQuit(address indexed sender, uint256 graceAmount);
    event PullRequested(uint256[] amounts, IERC20[] tokens, address dst);
    event PullExecuted(uint256[] amounts, IERC20[] tokens, address dst);
}