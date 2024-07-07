// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {WstethFeed} from "src/feeds/WstethFeed.sol";

contract Api3MainnetDeployer is Script {

    address stethFeed = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address ethFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

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
        new WstethFeed(stethFeed, ethFeed, wsteth);
    }
}