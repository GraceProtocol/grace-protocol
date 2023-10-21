// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./Pool.sol";

contract PoolDeployer {
    function deployPool(address underlying) external returns (address pool) {
        pool = address(new Pool(IPoolUnderlying(underlying), msg.sender));
    }
}