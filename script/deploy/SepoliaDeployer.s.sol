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
import {ClaimHelper} from "src/ClaimHelper.sol";

interface IERC20Metadata {
    function symbol() external view returns (string memory);
}

contract SepoliaDeployerScript is Script {

    address deployer; // avoid stack too deep error

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
            Deploy dependencies
        */
        PoolDeployer poolDeployer = new PoolDeployer();
        CollateralDeployer collateralDeployer = new CollateralDeployer();
        Oracle oracle = new Oracle();
        RateProvider rateProvider = new RateProvider();
        BorrowController borrowController = new BorrowController();
        RateModel rateModel = new RateModel(8000, 100, 100, 2500, 10000);
        new ClaimHelper();
        new Lens();
        // WETH address used on Base
        address weth = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

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
        deployPool(core, vaultFactory, Dai, address(0), 1e18, 10_000_000 * 1e18);

        /*
            Deploy Dola pool and vault
        */
        address Dola = address(new ERC20());
        ERC20(payable(Dola)).setName("Dola USD Stablecoin");
        ERC20(payable(Dola)).setSymbol("DOLA");
        ERC20(payable(Dola)).mint(deployer, 1_000_000 * 1e18);
        deployPool(core, vaultFactory, Dola, address(0), 1e18, 10_000_000 * 1e18);
                
        /*
            Deploy USDC pool and vault
        */
        address USDC = address(new ERC20());
        ERC20(payable(USDC)).setName("USDC");
        ERC20(payable(USDC)).setSymbol("USDC");
        ERC20(payable(USDC)).setDecimals(6);
        ERC20(payable(USDC)).mint(deployer, 1_000_000 * 1e6);
        deployPool(core, vaultFactory, USDC, address(0), 1e18 * (10 ** (18-6)), 10_000_000 * 1e6);

        /*
            Deploy WBTC pool and vault
        */
        address WBTC = address(new ERC20());
        ERC20(payable(WBTC)).setName("WBTC");
        ERC20(payable(WBTC)).setSymbol("WBTC");
        ERC20(payable(WBTC)).setDecimals(8);
        ERC20(payable(WBTC)).mint(deployer, 1_000_000 * 1e8);
        address wbtcFeed = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
        deployPool(core, vaultFactory, WBTC, wbtcFeed, 0, 10_000_000 * 1e8);

        /*
            Deploy WETH pool and vault
        */
        address ethFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        deployPool(core, vaultFactory, weth, ethFeed, 0, 10_000 * 1e18);

        /*
            Deploy WETH collateral
        */
        deployCollateral(core, weth, ethFeed, 8000, 1_000_000 * 1e18);

        /*
            Deploy Dai collateral
        */
        address daiFeed = 0x14866185B1962B63C3Ea9E03Bc1da838bab34C19;
        deployCollateral(core, Dai, daiFeed, 8000, 1_000_000 * 1e18);

        /*
            Deploy USDC collateral
        */
        address usdcFeed = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
        deployCollateral(core, USDC, usdcFeed, 8000, 1_000_000 * 1e18);

        /*
            Deploy WBTC collateral
        */
        deployCollateral(core, WBTC, wbtcFeed, 8000, 1_000_000 * 1e18);

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
