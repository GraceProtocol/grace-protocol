// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {API3Feed} from "src/feeds/API3Feed.sol";

contract Api3MainnetDeployer is Script {

    address feed = 0xb0935AAcBa65A724b51A3f8F17b684C3d511F46A;

    address deployer;
    function setUp() public {}

    function run() public {
        /*
            Setup
        */
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        require(deployer != address(0), "deployer address is 0x0");
        vm.startBroadcast(deployerPrivateKey);

        /*
            Deploy feed
        */
        new API3Feed(feed);
    }
}