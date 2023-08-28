// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

contract MockCore {

    bool public value = true;
    uint public collateralFeeBps;
    address public collateralFeeTo;

    function setValue (bool _value) public {
        value = _value;
    }

    function setCollateralFeeBps (uint256 _fee, address _dest) public {
        collateralFeeBps = _fee;
        collateralFeeTo = _dest;
    }

    function onCollateralDeposit(address, address, uint256) external returns (bool) {
        return value;
    }
    
    function onCollateralWithdraw(address, uint256) external returns (bool) {
        return value;
    }

    function getCollateralFeeBps(address) external view returns (uint256, address) {
        return (collateralFeeBps, collateralFeeTo);
    }
}