// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import {UtilLib} from "./utils/UtilLib.sol";
import {LRTConstants} from "./utils/LRTConstants.sol";
import {LRTConfigRoleChecker, ILRTConfig} from "./utils/LRTConfigRoleChecker.sol";

import {INodeDelegator} from "./interfaces/INodeDelegator.sol";
import {IDelegationManager, ISignatureUtils} from "./interfaces/IEigenDelegationManager.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IEigenStrategyManager} from "./interfaces/IEigenStrategyManager.sol";
import {IEigenDelayedWithdrawalRouter} from "./interfaces/IEigenDelayedWithdrawalRouter.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IEigenPodManager} from "./interfaces/IEigenPodManager.sol";
import {IEigenPod} from "./interfaces/IEigenPod.sol";

/// @title NodeDelegator Contract
/// @notice The contract that handles the depositing of assets into strategies
contract NodeDelegator is INodeDelegator, LRTConfigRoleChecker, PausableUpgradeable, ReentrancyGuardUpgradeable {
    /// @dev The EigenPod is created and owned by this contract
    IEigenPod public eigenPod;
    /// @dev Tracks the balance staked to validators and has yet to have the credentials verified with EigenLayer.
    /// call verifyWithdrawalCredentialsAndBalance in EL to verify the validator credentials on EigenLayer
    uint256 public stakedButUnverifiedNativeETH;

    mapping(bytes32 => address) realWithdrawers;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param lrtConfigAddr LRT config address
    function initialize(address lrtConfigAddr) external initializer {
        UtilLib.checkNonZeroAddress(lrtConfigAddr);
        __Pausable_init();
        __ReentrancyGuard_init();

        lrtConfig = ILRTConfig(lrtConfigAddr);
        emit UpdatedLRTConfig(lrtConfigAddr);
    }

    function createEigenPod() external onlyLRTManager {
        IEigenPodManager eigenPodManager = IEigenPodManager(lrtConfig.getContract(LRTConstants.EIGEN_POD_MANAGER));
        eigenPodManager.createPod();
        eigenPod = eigenPodManager.ownerToPod(address(this));

        emit EigenPodCreated(address(eigenPod), address(this));
    }

    /// @notice Approves the maximum amount of an asset to the eigen strategy manager
    /// @dev only supported assets can be deposited and only called by the LRT manager
    /// @param asset the asset to deposit
    function maxApproveToEigenStrategyManager(address asset)
        external
        override
        onlySupportedAsset(asset)
        onlyLRTManager
    {
        address eigenlayerStrategyManagerAddress = lrtConfig.getContract(LRTConstants.EIGEN_STRATEGY_MANAGER);
        IERC20(asset).approve(eigenlayerStrategyManagerAddress, type(uint256).max);
    }

    /// @notice Deposits an asset lying in this NDC into its strategy
    /// @dev only supported assets can be deposited and only called by the LRT manager
    /// @param asset the asset to deposit
    function depositAssetIntoStrategy(address asset)
        external
        override
        whenNotPaused
        nonReentrant
        onlySupportedAsset(asset)
        onlyLRTManager
    {
        address strategy = lrtConfig.assetStrategy(asset);
        if (strategy == address(0)) {
            revert StrategyIsNotSetForAsset();
        }

        IERC20 token = IERC20(asset);
        address eigenlayerStrategyManagerAddress = lrtConfig.getContract(LRTConstants.EIGEN_STRATEGY_MANAGER);

        uint256 balance = token.balanceOf(address(this));

        IEigenStrategyManager(eigenlayerStrategyManagerAddress).depositIntoStrategy(IStrategy(strategy), token, balance);

        emit AssetDepositIntoStrategy(asset, strategy, balance);
    }

    /// @notice Delegates this NodeDelegator to an EL operator
    /// @dev operators should be a valid EL operator
    /// @param operator the operator to delegate to
    function delegateTo(address operator) external whenNotPaused nonReentrant onlyLRTManager {
        address eigenlayerStrategyManagerAddress = lrtConfig.getContract(LRTConstants.EIGEN_STRATEGY_MANAGER);

        IEigenStrategyManager strategyManager = IEigenStrategyManager(eigenlayerStrategyManagerAddress);
        IDelegationManager delegationManager = IDelegationManager(strategyManager.delegation());

        ISignatureUtils.SignatureWithExpiry memory emptySignature;
        delegationManager.delegateTo(operator, emptySignature, "");
    }

    /// @notice Undelegates this NodeDelegator from an EL operator
    /// @dev locks new withdrawals from being initiated
    function undelegate() external whenNotPaused nonReentrant onlyLRTManager {
        address eigenlayerStrategyManagerAddress = lrtConfig.getContract(LRTConstants.EIGEN_STRATEGY_MANAGER);

        IEigenStrategyManager strategyManager = IEigenStrategyManager(eigenlayerStrategyManagerAddress);
        IDelegationManager delegationManager = IDelegationManager(strategyManager.delegation());

        delegationManager.undelegate(address(this));
    }

    /// @notice Initiates a withdrawal from EL
    /// @dev can be called only by LRTDepositPool
    /// @param asset address of the asset (stEth)
    /// @param amount amount of stEth tokens to withdraw
    /// @param withdrawer the withdrawer
    function queueWithdrawal(
        address asset,
        uint256 amount,
        address withdrawer
    ) external whenNotPaused nonReentrant onlySupportedAsset(asset) onlyDepositPool returns (bytes32[] memory) {
        address eigenlayerStrategyManagerAddress = lrtConfig.getContract(LRTConstants.EIGEN_STRATEGY_MANAGER);

        IEigenStrategyManager strategyManager = IEigenStrategyManager(eigenlayerStrategyManagerAddress);
        IDelegationManager delegationManager = IDelegationManager(strategyManager.delegation());
        require(delegationManager.delegatedTo(address(this)) != address(0), "cannot withdraw when undelegated");

        IStrategy strategy = IStrategy(lrtConfig.assetStrategy(asset));

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(lrtConfig.assetStrategy(asset));

        uint256[] memory shares = new uint256[](1);
        shares[0] = strategy.underlyingToSharesView(amount);

        IDelegationManager.QueuedWithdrawalParams memory withdrawParams = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategies,
            shares: shares,
            withdrawer: address(this)
        });
        IDelegationManager.QueuedWithdrawalParams[] memory params = new IDelegationManager.QueuedWithdrawalParams[](1);
        params[0] = withdrawParams;

        bytes32[] memory responses = delegationManager.queueWithdrawals(params);
        realWithdrawers[responses[0]] = withdrawer;
        return responses;
    }

    /// @notice Complete a previously initiated withdraw
    /// @dev can be called only by LRTDepositPool
    /// @param withdrawal Withdrawal data
    /// @param asset address of the asset (stEth)
    /// @param withdrawer the withdrawer
    function completeWithdrawal(
        IDelegationManager.Withdrawal calldata withdrawal,
        address asset,
        address withdrawer
    ) public whenNotPaused nonReentrant onlySupportedAsset(asset) onlyDepositPool {
        address eigenlayerStrategyManagerAddress = lrtConfig.getContract(LRTConstants.EIGEN_STRATEGY_MANAGER);

        IEigenStrategyManager strategyManager = IEigenStrategyManager(eigenlayerStrategyManagerAddress);
        IDelegationManager delegationManager = IDelegationManager(strategyManager.delegation());
        bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);
        IERC20[] memory tokens = new IERC20[](1);
        IERC20 token = IERC20(asset);
        tokens[0] = token;
        //it was withdrawn by a user, not via undelegate
        if (realWithdrawers[withdrawalRoot] != address(0)) {
            require(withdrawer == realWithdrawers[withdrawalRoot]);
            uint256 balanceOld = token.balanceOf(address(this));
            delegationManager.completeQueuedWithdrawal(withdrawal, tokens, 0, true);
            uint256 delta = token.balanceOf(address(this)) - balanceOld;
            token.transfer(withdrawer, delta);
        } else {
            delegationManager.completeQueuedWithdrawal(withdrawal, tokens, 0, true);
        }
    }

    /// @notice Transfers an asset back to the LRT deposit pool
    /// @dev only supported assets can be transferred and only called by the LRT manager
    /// @param asset the asset to transfer
    /// @param amount the amount to transfer
    function transferBackToLRTDepositPool(
        address asset,
        uint256 amount
    ) external whenNotPaused nonReentrant onlySupportedAsset(asset) onlyLRTManager {
        address lrtDepositPool = lrtConfig.getContract(LRTConstants.LRT_DEPOSIT_POOL);

        bool success;
        success = IERC20(asset).transfer(lrtDepositPool, amount);

        if (!success) {
            revert TokenTransferFailed();
        }
    }

    /// @notice Fetches balance of all assets staked in eigen layer through this contract
    /// @return assets the assets that the node delegator has deposited into strategies
    /// @return assetBalances the balances of the assets that the node delegator has deposited into strategies
    function getAssetBalances()
        external
        view
        override
        returns (address[] memory assets, uint256[] memory assetBalances)
    {
        address eigenlayerStrategyManagerAddress = lrtConfig.getContract(LRTConstants.EIGEN_STRATEGY_MANAGER);

        (IStrategy[] memory strategies,) =
            IEigenStrategyManager(eigenlayerStrategyManagerAddress).getDeposits(address(this));

        uint256 strategiesLength = strategies.length;
        assets = new address[](strategiesLength);
        assetBalances = new uint256[](strategiesLength);

        for (uint256 i = 0; i < strategiesLength;) {
            assets[i] = address(IStrategy(strategies[i]).underlyingToken());
            assetBalances[i] = IStrategy(strategies[i]).userUnderlyingView(address(this));
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Returns the balance of an asset that the node delegator has deposited into the strategy
    /// @param asset the asset to get the balance of
    /// @return stakedBalance the balance of the asset
    function getAssetBalance(address asset) public view override returns (uint256) {
        address strategy = lrtConfig.assetStrategy(asset);
        if (strategy == address(0)) {
            return 0;
        }

        return IStrategy(strategy).userUnderlyingView(address(this));
    }

    /// @dev Returns the balance of an asset that the node delegator has deposited into its EigenPod strategy
    function getETHEigenPodBalance() external view override returns (uint256 ethStaked) {
        // TODO: Implement functionality to manage pending withdrawals and accommodate negative shares once withdrawal
        // feature is activated. Additionally, ensure verification of both staked but unverified and staked and verified
        // ETH native supply NDCs as provided to Eigenlayer.
        ethStaked = stakedButUnverifiedNativeETH;
    }

    /// @dev initiate a delayed withdraw of the ETH before the eigenpod is verified
    /// which will be available to claim after withdrawalDelay blocks
    function initiateWithdrawRewards() external onlyLRTOperator {
        uint256 eigenPodBalance = address(eigenPod).balance;
        uint256 ethValidatorMinBalanceThreshold = 16 ether;
        if (eigenPodBalance > ethValidatorMinBalanceThreshold) {
            revert InvalidRewardAmount();
        }

        eigenPod.withdrawBeforeRestaking();
        emit ETHRewardsWithdrawInitiated(eigenPodBalance);
    }

    /// @dev claims back the withdrawal amount initiated to this nodeDelegator contract
    /// once withdrawal amount is claimable
    function claimRewards(uint256 maxNumberOfDelayedWithdrawalsToClaim) external onlyLRTOperator {
        uint256 balanceBefore = address(this).balance;
        address delayedRouterAddr = eigenPod.delayedWithdrawalRouter();
        IEigenDelayedWithdrawalRouter elDelayedRouter = IEigenDelayedWithdrawalRouter(delayedRouterAddr);
        elDelayedRouter.claimDelayedWithdrawals(address(this), maxNumberOfDelayedWithdrawalsToClaim);
        uint256 balanceAfter = address(this).balance;

        emit ETHRewardsClaimed(balanceAfter - balanceBefore);
    }

    /// @dev Triggers stopped state. Contract must not be paused.
    function pause() external onlyLRTManager {
        _pause();
    }

    /// @dev Returns to normal state. Contract must be paused
    function unpause() external onlyLRTAdmin {
        _unpause();
    }

    /// @dev allow NodeDelegator to receive ETH
    receive() external payable {}
}
