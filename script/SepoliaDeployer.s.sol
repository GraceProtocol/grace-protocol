// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {PoolDeployer} from "src/PoolDeployer.sol";
import {CollateralDeployer} from "src/CollateralDeployer.sol";
import {Core, IRateModel} from "src/Core.sol";
import {RateModel} from "src/RateModel.sol";
import {Grace} from "src/GRACE.sol";
import {Reserve, IERC20} from "src/Reserve.sol";
import {Timelock} from "src/Timelock.sol";
import {GovernorAlpha} from "src/GovernorAlpha.sol";
import {FixedPriceFeed} from "src/FixedPriceFeed.sol";
import {BondFactory} from "src/BondFactory.sol";
import {Helper} from "src/Helper.sol";

interface IERC20Metadata {
    function symbol() external view returns (string memory);
}

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
        // deploy interest rate model
        RateModel rateModel = new RateModel(address(core));
        // connect them to core
        core.setDefaultInterestRateModel(IRateModel(address(rateModel)));
        core.setDefaultCollateralFeeModel(IRateModel(address(rateModel)));
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
        // deploy Helper
        new Helper(weth);
        // Deploy Bond Factory
        BondFactory bondFactory = new BondFactory(address(grace), deployer);
        // Set Bond Factory as Grace minter
        grace.setMinter(address(bondFactory), type(uint).max, 1000 * 1e18);

        // Deploy fixed price USDC feed
        FixedPriceFeed usdcPriceFeed = new FixedPriceFeed(8, 100000000);
        // 8 decimal token
        address YEENUS = 0x93fCA4c6E2525C09c95269055B46f16b1459BF9d;
        // Deploy USDC pool (YEENUS) and bond
        deployPool(core, bondFactory, YEENUS, address(usdcPriceFeed), 1_000_000 * 1e8);

        // Chainlink feed on Sepolia
        address ethFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        // Deploy WETH collateral
        deployCollateral(core, weth, ethFeed, 8000, 1000 * 1e18, 2000);

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

    function deployPool(
        Core core,
        BondFactory bondFactory, // if address(0), no bond will be created
        address asset,
        address feed,
        uint depositCap) public returns (address pool, address bond) {
        string memory name = string(abi.encodePacked("Grace ", IERC20Metadata(asset).symbol(), " Pool"));
        string memory symbol = string(abi.encodePacked("gp", IERC20Metadata(asset).symbol()));
        pool = core.deployPool(name, symbol, asset, feed, depositCap);
        if(address(bondFactory) != address(0)) {
            string memory bondName = string(abi.encodePacked("Grace ", IERC20Metadata(asset).symbol(), " 1-week bond"));
            string memory bondSymbol = string(abi.encodePacked("gb", IERC20Metadata(asset).symbol(), "-1W"));
            uint bondStart = block.timestamp + 600; // after 10 minutes to leave time for the bond to be created
            uint bondDuration = 7 days;
            uint auctionDuration = 1 days;
            uint initialBudget = 1000 * 1e18;
            bond = bondFactory.createBond(
                pool,
                bondName,
                bondSymbol,
                bondStart,
                bondDuration,
                auctionDuration,
                initialBudget
            );
        }
    }

    function deployCollateral(
        Core core,
        address underlying,
        address feed,
        uint collateralFactorBps,
        uint hardCapUsd,
        uint softCapBps) public returns (address) {
        string memory name = string(abi.encodePacked("Grace ", IERC20Metadata(underlying).symbol(), " Collateral"));
        string memory symbol = string(abi.encodePacked("gc", IERC20Metadata(underlying).symbol()));
        return core.deployCollateral(name, symbol, underlying, feed, collateralFactorBps, hardCapUsd, softCapBps);
    }
}
