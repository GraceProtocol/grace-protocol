// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {PoolDeployer} from "src/PoolDeployer.sol";
import {CollateralDeployer} from "src/CollateralDeployer.sol";
import {Core} from "src/Core.sol";
import {RateModel} from "src/RateModel.sol";
import {GTR} from "src/GTR.sol";
import {Reserve, IERC20} from "src/Reserve.sol";
import {FixedPriceFeed} from "test/mocks/FixedPriceFeed.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {Oracle} from "src/Oracle.sol";
import {RateProvider} from "src/RateProvider.sol";
import {BorrowController} from "src/BorrowController.sol";
import {ERC20} from "test/mocks/ERC20.sol";
import {Lens} from "src/Lens.sol";

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
        RateModel rateModel = new RateModel(8000, 1 days, 0, 2000, 10000);
        new Lens();
        // WETH address used on Arbitrum Sepolia
        address weth = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;

        /*
            Deploy Core
        */
        Core core = new Core(
            address(rateProvider),
            address(borrowController),
            address(oracle),
            address(poolDeployer),
            address(collateralDeployer),
            weth
        );

        /*
            Configure RateProvider
        */
        rateProvider.setDefaultCollateralFeeModel(address(rateModel));
        rateProvider.setDefaultInterestRateModel(address(rateModel));

        /*
            Deploy GTR
        */        
        GTR gtr = new GTR(deployer);

        /*
            Deploy Reserve
        */   
        Reserve reserve = new Reserve(address(gtr));
        // Set reserve as fee destination
        core.setFeeDestination(address(reserve));

        /*
            Deploy VaultFactory
        */  
        VaultFactory vaultFactory = new VaultFactory(address(gtr), weth, 100000 * 1e18);
        // Set vaultFactory as Grace minter
        gtr.setMinter(address(vaultFactory), type(uint).max);

        /*
            Deploy Dai pool and vault
        */
        address Dai = address(new ERC20());
        ERC20(payable(Dai)).setName("Dai");
        ERC20(payable(Dai)).setSymbol("DAI");
        ERC20(payable(Dai)).mint(deployer, 1_000_000 * 1e18);
        deployPool(core, vaultFactory, Dai, address(0), 1e18, 1_000_000 * 1e18);

        /*
            Deploy Dola pool and vault
        */
        address Dola = address(new ERC20());
        ERC20(payable(Dola)).setName("Dola USD Stablecoin");
        ERC20(payable(Dola)).setSymbol("DOLA");
        ERC20(payable(Dola)).mint(deployer, 1_000_000 * 1e18);
        deployPool(core, vaultFactory, Dola, address(0), 1e18, 1_000_000 * 1e18);

        /*
            Deploy WETH pool and vault
        */
        address ethFeed = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
        deployPool(core, vaultFactory, weth, ethFeed, 0, 1_000 * 1e18);

        /*
            Deploy WETH collateral
        */
        deployCollateral(core, weth, ethFeed, 8000, 1000000 * 1e18);
        address _deployer = deployer;

        /*
            Deploy Dai collateral
        */
        address daiFeed = 0xb113F5A928BCfF189C998ab20d753a47F9dE5A61;
        deployCollateral(core, Dai, daiFeed, 8000, 1000000 * 1e18);

        /*
            Deploy Arb collateral
        */
        address Arb = address(new ERC20());
        address arbFeed = 0xD1092a65338d049DB68D7Be6bD89d17a0929945e;
        ERC20(payable(Arb)).setName("Arbitrum");
        ERC20(payable(Arb)).setSymbol("ARB");
        ERC20(payable(Arb)).mint(_deployer, 1_000_000 * 1e18);
        deployCollateral(core, Arb, arbFeed, 8000, 1000000 * 1e18);


        vm.stopBroadcast();
    }

    function deployPool(
        Core core,
        VaultFactory vaultFactory, // if address(0), no vault will be created
        address asset,
        address feed,
        uint fixedPrice,
        uint depositCap) public returns (address pool, address vault) {
        string memory name = string(abi.encodePacked("Grace ", IERC20Metadata(asset).symbol(), " Pool"));
        string memory symbol = string(abi.encodePacked("gp", IERC20Metadata(asset).symbol()));
        Oracle oracle = Oracle(address(core.oracle()));
        if(feed != address(0)) {
            oracle.setPoolFeed(asset, feed);
        } else {
            oracle.setPoolFixedPrice(asset, fixedPrice);
        }
        pool = core.deployPool(name, symbol, asset, depositCap);
        if(address(vaultFactory) != address(0)) {
            vault = vaultFactory.createVault(
                pool,
                1
            );
        }
    }

    function deployCollateral(
        Core core,
        address underlying,
        address feed,
        uint collateralFactorBps,
        uint hardCapUsd) public returns (address) {
        Oracle oracle = Oracle(address(core.oracle()));
        oracle.setCollateralFeed(underlying, feed);
        return core.deployCollateral(underlying, collateralFactorBps, hardCapUsd);
    }
}
