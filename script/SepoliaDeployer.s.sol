// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {PoolDeployer} from "src/PoolDeployer.sol";
import {CollateralDeployer} from "src/CollateralDeployer.sol";
import {Core, IInterestRateController, ICollateralFeeController} from "src/Core.sol";
import {InterestRateController} from "src/InterestRateController.sol";
import {CollateralFeeController} from "src/CollateralFeeController.sol";
import {Grace} from "src/GRACE.sol";
import {Reserve, IERC20} from "src/Reserve.sol";
import {Timelock} from "src/Timelock.sol";
import {GovernorAlpha} from "src/GovernorAlpha.sol";
import {FixedPriceFeed} from "src/FixedPriceFeed.sol";
import {BondFactory} from "src/BondFactory.sol";
import {EthHelper} from "src/EthHelper.sol";

contract MainnetDeployerScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        // deployer pool deployer
        PoolDeployer poolDeployer = new PoolDeployer();
        // deployer collateral deployer
        CollateralDeployer collateralDeployer = new CollateralDeployer();
        // deploy core
        Core core = new Core(deployer, address(poolDeployer), address(collateralDeployer));
        // deploy interest rate controller
        InterestRateController irc = new InterestRateController(address(core));
        // deploy collateral fee controller
        CollateralFeeController cfc = new CollateralFeeController(address(core));
        // connect them to core
        core.setInterestRateController(IInterestRateController(address(irc)));
        core.setCollateralFeeController(ICollateralFeeController(address(cfc)));
        // Deploy Timelock
        Timelock timelock = new Timelock(deployer);
        // deploy GRACE
        Grace grace = new Grace(deployer);
        // deploy Reserve
        Reserve reserve = new Reserve(IERC20(address(grace)), address(timelock));
        // Set reserve as fee destination
        core.setFeeDestination(address(reserve));
        // WETH address used by Uniswap on Sepolia
        address weth = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        // deploy EthHelper
        new EthHelper(weth);

        // Deploy fixed price USDC feed
        FixedPriceFeed usdcPriceFeed = new FixedPriceFeed(8, 100000000);
        // 8 decimal token
        address YEENUS = 0x93fCA4c6E2525C09c95269055B46f16b1459BF9d;
        // Deploy USDC pool (YEENUS)
        address usdcPool = core.deployPool("Grace USDC", "gUSDC", YEENUS, address(usdcPriceFeed), 100000 * 1e6);

        // Chainlink feed on Sepolia
        address ethFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        // Deploy WETH collateral
        core.deployCollateral("Grace Collateral WETH", "gcWETH", weth, ethFeed, 8500, 1_000_000 ether, 2000);
        
        // Deploy Bond Factory
        BondFactory bondFactory = new BondFactory(address(grace), deployer);
        // Set Bond Factory as Grace minter
        grace.setMinter(address(bondFactory), type(uint).max, 1000 * 1e18);
        // Create USDC pool bond
        bondFactory.createBond(
            usdcPool,
            "Grace USDC 1-week bond",
            "G-USDC-1W",
            block.timestamp + 600, // after 10 minutes to leave time for the bond to be created
            7 days,
            1 days,
            1000 * 1e18
        );

        // Set BondFactory operator to timelock
        bondFactory.setOperator(address(timelock));
        // Set core ownership to timelock
        core.setOwner(address(timelock));
        // Set grace ownership to timelock
        grace.setOperator(address(timelock));
        // to avoid stack too deep
        uint _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address _deployer = vm.addr(_deployerPrivateKey);
        // Deploy GovernorAlpha
        GovernorAlpha governor = new GovernorAlpha(address(timelock), address(grace), _deployer);
        // Set governor as pending admin of timelock
        timelock.setPendingAdmin(address(governor));
        // Accept new admin of govenor
        governor.__acceptAdmin();

        vm.stopBroadcast();
    }
}
