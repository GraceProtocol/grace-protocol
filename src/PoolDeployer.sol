// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./Pool.sol";

contract PoolDeployer {
    function deployPool(string memory name, string memory symbol, address underlying) external returns (address pool) {
        pool = address(new Pool(name, symbol, IPoolUnderlying(underlying), msg.sender));
    }
}