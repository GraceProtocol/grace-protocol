// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {Oracle} from "src/Oracle.sol";

contract SetCapUsd is Script {

    Oracle oracle = Oracle(0x62dE0B76eB5c647A91c96b535111fEd071a051e5);
    address token = address(0);
    uint price = 1e18;

    function setUp() public {}

    function run() public {
        /*
            Setup
        */
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /*
            Set capUsd
        */
        oracle.setPoolFixedPrice(token, price);
    
        vm.stopBroadcast();
    }

}