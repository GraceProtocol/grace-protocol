// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Core, IInterestRateController, ICollateralFeeController} from "src/Core.sol";
import {InterestRateController} from "src/InterestRateController.sol";
import {CollateralFeeController} from "src/CollateralFeeController.sol";
import {Grace} from "src/GRACE.sol";
import {Reserve, IERC20} from "src/Reserve.sol";
import {Timelock} from "src/Timelock.sol";
import {GovernorAlpha} from "src/GovernorAlpha.sol";
import {FixedPriceFeed} from "src/FixedPriceFeed.sol";

contract SepoliaDeployerScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // deploy core
        Core core = new Core(address(this));
        // deploy interest rate controller
        InterestRateController irc = new InterestRateController(address(core));
        // deploy collateral fee controller
        CollateralFeeController cfc = new CollateralFeeController(address(core));
        // connect them to core
        core.setInterestRateController(IInterestRateController(address(irc)));
        core.setCollateralFeeController(ICollateralFeeController(address(cfc)));
        // Deploy Timelock
        Timelock timelock = new Timelock(address(this));
        // deploy GRACE
        Grace grace = new Grace(address(timelock));
        // deploy Reserve
        Reserve reserve = new Reserve(IERC20(address(grace)), address(timelock));
        // Set reserve as fee destination
        core.setFeeDestination(address(reserve));
        
        // Deploy fixed price USDC feed
        FixedPriceFeed usdcPriceFeed = new FixedPriceFeed(8, 100000000);
        // 8 decimal token
        address YEENUS = 0x93fCA4c6E2525C09c95269055B46f16b1459BF9d;
        // Deploy USDC pool
        core.deployPool(YEENUS, address(usdcPriceFeed), 100000 * 1e6);

        // Chainlink feed on Sepolia
        address ethFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        // WETH address used by Uniswap on Sepolia
        address weth = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        // Deploy WETH collateral
        core.deployCollateral(weth, ethFeed, 8500, 1_000_000 ether, 2000);
        
        // Set core ownership to timelock
        core.setOwner(address(timelock));
        // Deploy GovernorAlpha
        GovernorAlpha governor = new GovernorAlpha(address(timelock), address(grace), address(this));
        // Set governor as pending admin of timelock
        timelock.setPendingAdmin(address(governor));
        // Accept new admin of govenor
        governor.__acceptAdmin();
        // Set deployer as guardian to deployer
        governor.__transferGuardianship(msg.sender);
    }
}
