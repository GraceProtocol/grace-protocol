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

    IERC20 public immutable grace;
    uint constant MANTISSA = 1e18;
    uint locked = 1; // 1 = unlocked, 2 = locked

    constructor(IERC20 _grace) {
        grace = _grace;
    }

    function redeem(uint256 amount, IERC20[] memory tokens) external {
        require(locked == 1, "locked");
        locked = 2;
        grace.transferFrom(msg.sender, address(this), amount);
        uint totalSupply = grace.totalSupply();
        grace.burn(amount);
        uint shareMantissa = amount * MANTISSA / totalSupply;
        for(uint i = 0; i < tokens.length; i++) {
            for(uint j = i + 1; j < tokens.length; j++) {
                require(tokens[i] != tokens[j], "duplicate token");
            }
            uint balance = tokens[i].balanceOf(address(this));
            require(balance > 0, "zeroBalance");
            uint share = balance * shareMantissa / MANTISSA;
            tokens[i].transfer(msg.sender, share);
        }
        locked = 1;
    }
}