// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "./Pool.sol";

contract PoolDeployer {
    function deployPool(string memory name, string memory symbol, address underlying, bool isWETH) external returns (address pool) {
        pool = address(new Pool(name, symbol, IERC20(underlying), isWETH, msg.sender));
    }
}