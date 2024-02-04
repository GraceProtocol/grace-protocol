// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {Core, ICollateral} from "src/Core.sol";

interface IERC20Metadata {
    function symbol() external view returns (string memory);
}

contract SetCapUsd is Script {

    Core core = Core(0xFA07c2B82E82de8Ce888C61f7e14ca088684b075);
    ICollateral collateral = ICollateral(0x98f3d63929a9Cd641D51f6D6d57281e8DA8ACe5f);
    uint capUsd = 1_000_000 * 1e18;

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
        core.setCollateralCapUsd(collateral, capUsd);
    
        vm.stopBroadcast();
    }

}