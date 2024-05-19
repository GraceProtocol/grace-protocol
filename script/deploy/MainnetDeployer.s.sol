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

contract MainnetDeployerScript is Script {

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
        RateModel rateModel = new RateModel(8000, 100, 0, 2500, 10000);
        new Lens();
        // WETH address used on Base
        address weth = 0x4200000000000000000000000000000000000006;

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
            Deploy Dola pool and vault
        */
        address Dola = 0x4621b7A9c75199271F773Ebd9A499dbd165c3191;
        deployPool(core, vaultFactory, Dola, address(0), 1e18, 10000 * 1e18);
                
        /*
            Deploy USDC pool and vault
        */
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        deployPool(core, vaultFactory, USDC, address(0), 1e18 * (10 ** (18-6)), 10000 * 1e6);

        /*
            Deploy WETH collateral
        */
        address ethFeed = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
        deployCollateral(core, weth, ethFeed, 9000, 10000 * 1e18);

        /*
            Deploy AERO collateral
        */
        address aero = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
        address aeroFeed = 0x4EC5970fC728C5f65ba413992CD5fF6FD70fcfF0;
        deployCollateral(core, aero, aeroFeed, 8000, 10000 * 1e18);

        /*
            Transfer ownerships
        */
        address multisig = 0x986ed016Cc948641dB23749f97FC9Ab84B57d1Fc;
        oracle.setOwner(multisig);
        rateProvider.setOwner(multisig);
        borrowController.setOwner(multisig);
        core.setOwner(multisig);
        gtr.setOperator(multisig);
        reserve.setOwner(multisig);
        vaultFactory.setOperator(multisig);

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
