// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import "forge-std/Script.sol";

import {LRTConfig, LRTConstants} from "contracts/LRTConfig.sol";
import {MyRSETH} from "contracts/MyRSETH.sol";
import {IstETH} from "contracts/interfaces/IstETH.sol";
import {LRTDepositPool} from "contracts/LRTDepositPool.sol";
import {NodeDelegator} from "contracts/NodeDelegator.sol";
import {MultiSigWallet} from "contracts/MultiSigWallet.sol";

import {ProxyFactory} from "script/foundry-scripts/utils/ProxyFactory.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

function getLSTs() view returns (address stETH, address ethx) {
    uint256 chainId = block.chainid;

    if (chainId == 1) {
        // mainnet
        stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        ethx = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    } else if (chainId == 5) {
        // goerli
        stETH = 0x1643E812aE58766192Cf7D2Cf9567dF2C37e9B7F;
        ethx = 0x3338eCd3ab3d3503c55c931d759fA6d78d287236;
    } else {
        revert("Unsupported network");
    }
}

contract DeployLRT is Script {
    address public sender;
    address public proxyAdminOwner;
    ProxyAdmin public proxyAdmin;

    ProxyFactory public proxyFactory;

    LRTConfig public lrtConfigProxy;
    MyRSETH public RSETHProxy;
    LRTDepositPool public lrtDepositPoolProxy;
    NodeDelegator public nodeDelegatorProxy1;
    address[] public nodeDelegatorContracts;
    MultiSigWallet public multiSigProxy;
    address[] public adminList;

    uint256 public minAmountToDeposit;

    function maxApproveToEigenStrategyManager(address nodeDel) private {
        (address stETH, address ethx) = getLSTs();
        NodeDelegator(payable(nodeDel)).maxApproveToEigenStrategyManager(stETH);
    }

    function getAssetStrategies()
        private
        view
        returns (address strategyManager, address stETHStrategy, address ethXStrategy)
    {
        uint256 chainId = block.chainid;
        // https://github.com/Layr-Labs/eigenlayer-contracts#deployments
        if (chainId == 1) {
            // mainnet
            strategyManager = 0x858646372CC42E1A627fcE94aa7A7033e7CF075A;
            stETHStrategy = 0x93c4b944D05dfe6df7645A86cd2206016c51564D;
            // TODO: NEED TO HAVE ETHX STRATEGY
            ethXStrategy = 0x0000000000000000000000000000000000000000;
        } else {
            // testnet
            strategyManager = 0x779d1b5315df083e3F9E94cB495983500bA8E907;
            stETHStrategy = 0xB613E78E2068d7489bb66419fB1cfa11275d14da;
            // TODO: NEED TO HAVE ETHX STRATEGY
            ethXStrategy = 0x0000000000000000000000000000000000000000;
        }
    }

    function setUpByAdmin() private {
        (address stETH, address ethx) = getLSTs();
        // ----------- callable by admin ----------------

        // add rsETH to LRT config
        lrtConfigProxy.setRSETH(address(RSETHProxy));
        // call updateAssetStrategy for each asset in LRTConfig
        (address strategyManager, address stETHStrategy, address ethXStrategy) = getAssetStrategies();
        lrtConfigProxy.setContract(LRTConstants.EIGEN_STRATEGY_MANAGER, strategyManager);
        lrtConfigProxy.updateAssetStrategy(stETH, stETHStrategy);

        // grant MANAGER_ROLE to an address in LRTConfig
        lrtConfigProxy.grantRole(LRTConstants.MANAGER, proxyAdminOwner);
        // add minter role to lrtDepositPool so it mints rsETH
        lrtConfigProxy.grantRole(LRTConstants.MINTER_ROLE, address(lrtDepositPoolProxy));
        lrtConfigProxy.grantRole(LRTConstants.BURNER_ROLE, address(lrtDepositPoolProxy));

        // add nodeDelegators to LRTDepositPool queue
        nodeDelegatorContracts.push(address(nodeDelegatorProxy1));
        lrtDepositPoolProxy.addNodeDelegatorContractToQueue(nodeDelegatorContracts);

        // add min amount to deposit in LRTDepositPool
        lrtDepositPoolProxy.setMinAmountToDeposit(minAmountToDeposit);
    }

    function setUpByManager() private {
        (address stETH, address ethx) = getLSTs();
        // --------- callable by manager -----------
        // maxApproveToEigenStrategyManager in each NodeDelegator to transfer to strategy
        maxApproveToEigenStrategyManager(address(nodeDelegatorProxy1));
        vm.stopBroadcast();

        //hardcoded solution for inflation problem by minting dead shares
        vm.startBroadcast(0xde9be858da4a475276426320d5e9262ecfc3ba460bfac56360bfa6c4c28b4ee0);
        IstETH stEth = IstETH(stETH);
        stEth.submit{value: 2 * minAmountToDeposit}(address(0));
        stEth.approve(address(lrtDepositPoolProxy), type(uint256).max);
        uint256 minRsEthAmount = lrtDepositPoolProxy.getRsETHAmountToMint(address(stEth), minAmountToDeposit);
        lrtDepositPoolProxy.depositAsset(stETH, minAmountToDeposit, minRsEthAmount, "");
        vm.stopBroadcast();
        vm.startBroadcast();
    }

    function run() external {
        vm.startBroadcast();
        bytes32 salt = keccak256(abi.encodePacked("LRT-Stader-Labs"));
        proxyFactory = new ProxyFactory();
        proxyAdmin = new ProxyAdmin(); // msg.sender becomes the owner of ProxyAdmin

        proxyAdminOwner = proxyAdmin.owner();
        minAmountToDeposit = 0.0001 ether;

        console.log("ProxyAdmin deployed at: ", address(proxyAdmin));
        console.log("Owner of ProxyAdmin: ", proxyAdminOwner);

        address admin1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address admin2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

        // deploy implementation contracts
        address lrtConfigImplementation = address(new LRTConfig());
        address RSETHImplementation = address(new MyRSETH());
        address lrtDepositPoolImplementation = address(new LRTDepositPool());
        address nodeDelegatorImplementation = address(new NodeDelegator());
        address multiSigImplementation = address(new MultiSigWallet());

        console.log("-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=");
        console.log("LRTConfig implementation deployed at: ", lrtConfigImplementation);
        console.log("RSETH implementation deployed at: ", RSETHImplementation);
        console.log("LRTDepositPool implementation deployed at: ", lrtDepositPoolImplementation);
        console.log("NodeDelegator implementation deployed at: ", nodeDelegatorImplementation);
        console.log("MultiSig implementation deployed at: ", multiSigImplementation);
        console.log("-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=");

        // deploy proxy contracts and initialize them
        lrtConfigProxy = LRTConfig(proxyFactory.create(address(lrtConfigImplementation), address(proxyAdmin), salt));

        // set up LRTConfig init params
        (address stETH, address ethx) = getLSTs();
        address predictedRSETHAddress = proxyFactory.computeAddress(RSETHImplementation, address(proxyAdmin), salt);
        console.log("predictedRSETHAddress: ", predictedRSETHAddress);
        // init LRTConfig
        lrtConfigProxy.initialize(proxyAdminOwner, stETH, ethx, predictedRSETHAddress);

        multiSigProxy = MultiSigWallet(proxyFactory.create(address(multiSigImplementation), address(proxyAdmin), salt));
        adminList.push(admin1);
        adminList.push(admin2);
        multiSigProxy.initialize(adminList, 2);

        lrtDepositPoolProxy = LRTDepositPool(
            payable(proxyFactory.create(address(lrtDepositPoolImplementation), address(proxyAdmin), salt))
        );
        lrtDepositPoolProxy.initialize(address(lrtConfigProxy));

        // add deposit pool to LRT config
        lrtConfigProxy.setContract(LRTConstants.LRT_DEPOSIT_POOL, address(lrtDepositPoolProxy));

        RSETHProxy = MyRSETH(proxyFactory.create(address(RSETHImplementation), address(proxyAdmin), salt));
        RSETHProxy.initialize(proxyAdminOwner, address(lrtConfigProxy));

        nodeDelegatorProxy1 =
            NodeDelegator(payable(proxyFactory.create(address(nodeDelegatorImplementation), address(proxyAdmin), salt)));
        nodeDelegatorProxy1.initialize(address(lrtConfigProxy));

        console.log("LRTConfig proxy deployed at: ", address(lrtConfigProxy));
        console.log("MyRSETH proxy deployed at: ", address(RSETHProxy));
        console.log("LRTDepositPool proxy deployed at: ", address(lrtDepositPoolProxy));
        console.log("NodeDelegator proxy 1 deployed at: ", address(nodeDelegatorProxy1));
        console.log("MultiSig proxy deployed at: ", address(multiSigProxy));

        // setup
        setUpByAdmin();
        setUpByManager();

        lrtConfigProxy.grantRole(LRTConstants.MANAGER, admin1);
        lrtConfigProxy.grantRole(LRTConstants.MANAGER, address(multiSigProxy));
        lrtConfigProxy.grantRole(LRTConstants.DEFAULT_ADMIN_ROLE, admin1);
        lrtConfigProxy.grantRole(LRTConstants.DEFAULT_ADMIN_ROLE, address(multiSigProxy));
        // lrtConfigProxy.revokeRole(LRTConstants.DEFAULT_ADMIN_ROLE, proxyAdminOwner);
        proxyAdmin.transferOwnership(address(multiSigProxy));

        vm.stopBroadcast();
    }
}
