// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {RateModel} from "src/RateModel.sol";

interface IERC20Metadata {
    function symbol() external view returns (string memory);
}

contract RateModelMainnetDeployerScript is Script {
    
    uint public constant KINK_BPS = 8000;
    uint public constant MIN_RATE = 0;
    uint public constant KINK_RATE = 1500;
    uint public constant MAX_RATE = 10000;

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
            Deploy RateModel
        */
        new RateModel(KINK_BPS, MIN_RATE, KINK_RATE, MAX_RATE);
    }
}