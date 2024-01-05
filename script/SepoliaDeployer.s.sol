// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {PoolDeployer} from "src/PoolDeployer.sol";
import {CollateralDeployer} from "src/CollateralDeployer.sol";
import {Core} from "src/Core.sol";
import {RateModel} from "src/RateModel.sol";
import {Grace} from "src/GRACE.sol";
import {Reserve, IERC20} from "src/Reserve.sol";
import {FixedPriceFeed} from "test/mocks/FixedPriceFeed.sol";
import {BondFactory} from "src/BondFactory.sol";
import {Helper} from "src/Helper.sol";
import {Oracle} from "src/Oracle.sol";
import {RateProvider} from "src/RateProvider.sol";
import {BorrowController} from "src/BorrowController.sol";
import {ERC20} from "test/mocks/ERC20.sol";

interface IERC20Metadata {
    function symbol() external view returns (string memory);
}

contract SepoliaDeployerScript is Script {
    function setUp() public {}

    function run() public {
        /*
            Setup
        */
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        /*
            Deploy dependencies
        */
        PoolDeployer poolDeployer = new PoolDeployer();
        CollateralDeployer collateralDeployer = new CollateralDeployer();
        Oracle oracle = new Oracle();
        RateProvider rateProvider = new RateProvider();
        BorrowController borrowController = new BorrowController();
        RateModel rateModel = new RateModel(9000, 3 days, 0, 2000, 10000);
        // WETH address used on Arbitrum Sepolia
        address weth = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
        new Helper(weth);

        /*
            Deploy Core
        */
        Core core = new Core(
            address(rateProvider),
            address(borrowController),
            address(oracle),
            address(poolDeployer),
            address(collateralDeployer)
        );

        /*
            Configure RateProvider
        */
        rateProvider.setDefaultCollateralFeeModel(address(rateModel));
        rateProvider.setDefaultInterestRateModel(address(rateModel));

        /*
            Deploy GRACE
        */        
        Grace grace = new Grace(deployer);

        /*
            Deploy Reserve
        */   
        Reserve reserve = new Reserve(address(grace));
        // Set reserve as fee destination
        core.setFeeDestination(address(reserve));

        /*
            Deploy BondFactory
        */  
        BondFactory bondFactory = new BondFactory(address(grace));
        // Set Bond Factory as Grace minter
        grace.setMinter(address(bondFactory), type(uint).max, type(uint).max);

        /*
            Deploy USDC pool (YEENUS) and bond
        */
        address Dai = address(new ERC20());
        // Deploy Dai pool (mock) and bond
        deployPool(core, bondFactory, Dai, address(0), 1e18, 1_000_000 * 1e18);

        /*
            Deploy WETH collateral
        */
        // Chainlink feed on Sepolia
        address ethFeed = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
        // Deploy WETH collateral
        deployCollateral(core, weth, ethFeed, 8000, 1000 * 1e18, 2000);
        vm.stopBroadcast();
    }

    function deployPool(
        Core core,
        BondFactory bondFactory, // if address(0), no bond will be created
        address asset,
        address feed,
        uint fixedPrice,
        uint depositCap) public returns (address pool, address bond) {
        string memory name = string(abi.encodePacked("Grace ", IERC20Metadata(asset).symbol(), " Pool"));
        string memory symbol = string(abi.encodePacked("gp", IERC20Metadata(asset).symbol()));
        Oracle oracle = Oracle(address(core.oracle()));
        if(feed != address(0)) {
            oracle.setPoolFeed(asset, feed);
        } else {
            oracle.setPoolFixedPrice(asset, fixedPrice);
        }
        pool = core.deployPool(name, symbol, asset, depositCap);
        if(address(bondFactory) != address(0)) {
            string memory bondName = string(abi.encodePacked("Grace ", IERC20Metadata(asset).symbol(), " 1-hour bond"));
            string memory bondSymbol = string(abi.encodePacked("gb", IERC20Metadata(asset).symbol(), "-1H"));
            uint bondStart = block.timestamp + 600; // after 10 minutes to leave time for the bond to be created
            uint bondDuration = 60 minutes;
            uint auctionDuration = 10 minutes;
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
        Oracle oracle = Oracle(address(core.oracle()));
        oracle.setCollateralFeed(underlying, feed);
        return core.deployCollateral(name, symbol, underlying, collateralFactorBps, hardCapUsd, softCapBps);
    }
}
