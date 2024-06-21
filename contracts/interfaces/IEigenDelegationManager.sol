// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "./IEigenSignatureUtils.sol";
import "./IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title DelegationManager
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice  This is the contract for delegation in EigenLayer. The main functionalities of this contract are
 * - enabling anyone to register as an operator in EigenLayer
 * - allowing operators to specify parameters related to stakers who delegate to them
 * - enabling any staker to delegate its stake to the operator of its choice (a given staker can only delegate to a
 * single operator at a time)
 * - enabling a staker to undelegate its assets from the operator it is delegated to (performed as part of the
 * withdrawal process, initiated through the StrategyManager)
 */
interface IDelegationManager is ISignatureUtils {
    // @notice Struct used for storing information about a single operator who has registered with EigenLayer
    struct OperatorDetails {
        address earningsReceiver;
        address delegationApprover;
        uint32 stakerOptOutWindowBlocks;
    }

    struct StakerDelegation {
        address staker;
        address operator;
        uint256 nonce;
        uint256 expiry;
    }

    struct DelegationApproval {
        address staker;
        address operator;
        bytes32 salt;
        uint256 expiry;
    }

    struct Withdrawal {
        address staker;
        address delegatedTo;
        address withdrawer;
        uint256 nonce;
        uint32 startBlock;
        IStrategy[] strategies;
        uint256[] shares;
    }

    struct QueuedWithdrawalParams {
        IStrategy[] strategies;
        uint256[] shares;
        address withdrawer;
    }

    event OperatorRegistered(address indexed operator, OperatorDetails operatorDetails);
    event OperatorDetailsModified(address indexed operator, OperatorDetails newOperatorDetails);
    event OperatorMetadataURIUpdated(address indexed operator, string metadataURI);
    event OperatorSharesIncreased(address indexed operator, address staker, IStrategy strategy, uint256 shares);
    event OperatorSharesDecreased(address indexed operator, address staker, IStrategy strategy, uint256 shares);
    event StakerDelegated(address indexed staker, address indexed operator);
    event StakerUndelegated(address indexed staker, address indexed operator);
    event StakerForceUndelegated(address indexed staker, address indexed operator);
    event WithdrawalQueued(bytes32 withdrawalRoot, Withdrawal withdrawal);
    event WithdrawalCompleted(bytes32 withdrawalRoot);
    event WithdrawalMigrated(bytes32 oldWithdrawalRoot, bytes32 newWithdrawalRoot);
    event MinWithdrawalDelayBlocksSet(uint256 previousValue, uint256 newValue);
    event StrategyWithdrawalDelayBlocksSet(IStrategy strategy, uint256 previousValue, uint256 newValue);

    function registerAsOperator(
        OperatorDetails calldata registeringOperatorDetails,
        string calldata metadataURI
    ) external;

    function modifyOperatorDetails(OperatorDetails calldata newOperatorDetails) external;

    function updateOperatorMetadataURI(string calldata metadataURI) external;

    function delegateTo(
        address operator,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external;

    function delegateToBySignature(
        address staker,
        address operator,
        SignatureWithExpiry memory stakerSignatureAndExpiry,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external;

    function undelegate(address staker) external returns (bytes32[] memory withdrawalRoot);

    function queueWithdrawals(QueuedWithdrawalParams[] calldata queuedWithdrawalParams)
        external
        returns (bytes32[] memory);

    function completeQueuedWithdrawal(
        Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) external;

    function completeQueuedWithdrawals(
        Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool[] calldata receiveAsTokens
    ) external;

    /**
     * @notice Increases a staker's delegated share balance in a strategy.
     * @param staker The address to increase the delegated shares for their operator.
     * @param strategy The strategy in which to increase the delegated shares.
     * @param shares The number of shares to increase.
     *
     * @dev *If the staker is actively delegated*, then increases the `staker`'s delegated shares in `strategy` by
     * `shares`. Otherwise does nothing.
     * @dev Callable only by the StrategyManager or EigenPodManager.
     */
    function increaseDelegatedShares(address staker, IStrategy strategy, uint256 shares) external;

    /**
     * @notice Decreases a staker's delegated share balance in a strategy.
     * @param staker The address to increase the delegated shares for their operator.
     * @param strategy The strategy in which to decrease the delegated shares.
     * @param shares The number of shares to decrease.
     *
     * @dev *If the staker is actively delegated*, then decreases the `staker`'s delegated shares in `strategy` by
     * `shares`. Otherwise does nothing.
     * @dev Callable only by the StrategyManager or EigenPodManager.
     */
    function decreaseDelegatedShares(address staker, IStrategy strategy, uint256 shares) external;

    /**
     * @notice returns the address of the operator that `staker` is delegated to.
     * @notice Mapping: staker => operator whom the staker is currently delegated to.
     * @dev Note that returning address(0) indicates that the staker is not actively delegated to any operator.
     */
    function delegatedTo(address staker) external view returns (address);

    /**
     * @notice Returns the OperatorDetails struct associated with an `operator`.
     */
    function operatorDetails(address operator) external view returns (OperatorDetails memory);

    /*
     * @notice Returns the earnings receiver address for an operator
     */
    function earningsReceiver(address operator) external view returns (address);

    /**
     * @notice Returns the delegationApprover account for an operator
     */
    function delegationApprover(address operator) external view returns (address);

    /**
     * @notice Returns the stakerOptOutWindowBlocks for an operator
     */
    function stakerOptOutWindowBlocks(address operator) external view returns (uint256);

    /**
     * @notice Given array of strategies, returns array of shares for the operator
     */
    function getOperatorShares(
        address operator,
        IStrategy[] memory strategies
    ) external view returns (uint256[] memory);

    /**
     * @notice Given a list of strategies, return the minimum number of blocks that must pass to withdraw
     * from all the inputted strategies. Return value is >= minWithdrawalDelayBlocks as this is the global min
     * withdrawal delay.
     * @param strategies The strategies to check withdrawal delays for
     */
    function getWithdrawalDelay(IStrategy[] calldata strategies) external view returns (uint256);

    /**
     * @notice returns the total number of shares in `strategy` that are delegated to `operator`.
     * @notice Mapping: operator => strategy => total number of shares in the strategy delegated to the operator.
     * @dev By design, the following invariant should hold for each Strategy:
     * (operator's shares in delegation manager) = sum (shares above zero of all stakers delegated to operator)
     * = sum (delegateable shares of all stakers delegated to the operator)
     */
    function operatorShares(address operator, IStrategy strategy) external view returns (uint256);

    /**
     * @notice Returns 'true' if `staker` *is* actively delegated, and 'false' otherwise.
     */
    function isDelegated(address staker) external view returns (bool);

    /**
     * @notice Returns true is an operator has previously registered for delegation.
     */
    function isOperator(address operator) external view returns (bool);

    /// @notice Mapping: staker => number of signed delegation nonces (used in `delegateToBySignature`) from the staker
    /// that the contract has already checked
    function stakerNonce(address staker) external view returns (uint256);

    /**
     * @notice Mapping: delegationApprover => 32-byte salt => whether or not the salt has already been used by the
     * delegationApprover.
     * @dev Salts are used in the `delegateTo` and `delegateToBySignature` functions. Note that these functions only
     * process the delegationApprover's
     * signature + the provided salt if the operator being delegated to has specified a nonzero address as their
     * `delegationApprover`.
     */
    function delegationApproverSaltIsSpent(address _delegationApprover, bytes32 salt) external view returns (bool);

    /**
     * @notice Minimum delay enforced by this contract for completing queued withdrawals. Measured in blocks, and
     * adjustable by this contract's owner,
     * up to a maximum of `MAX_WITHDRAWAL_DELAY_BLOCKS`. Minimum value is 0 (i.e. no delay enforced).
     * Note that strategies each have a separate withdrawal delay, which can be greater than this value. So the minimum
     * number of blocks that must pass
     * to withdraw a strategy is MAX(minWithdrawalDelayBlocks, strategyWithdrawalDelayBlocks[strategy])
     */
    function minWithdrawalDelayBlocks() external view returns (uint256);

    /**
     * @notice Minimum delay enforced by this contract per Strategy for completing queued withdrawals. Measured in
     * blocks, and adjustable by this contract's owner,
     * up to a maximum of `MAX_WITHDRAWAL_DELAY_BLOCKS`. Minimum value is 0 (i.e. no delay enforced).
     */
    function strategyWithdrawalDelayBlocks(IStrategy strategy) external view returns (uint256);

    /// @notice return address of the beaconChainETHStrategy
    function beaconChainETHStrategy() external view returns (IStrategy);

    /**
     * @notice Calculates the digestHash for a `staker` to sign to delegate to an `operator`
     * @param staker The signing staker
     * @param operator The operator who is being delegated to
     * @param expiry The desired expiry time of the staker's signature
     */
    function calculateCurrentStakerDelegationDigestHash(
        address staker,
        address operator,
        uint256 expiry
    ) external view returns (bytes32);

    /**
     * @notice Calculates the digest hash to be signed and used in the `delegateToBySignature` function
     * @param staker The signing staker
     * @param _stakerNonce The nonce of the staker. In practice we use the staker's current nonce, stored at
     * `stakerNonce[staker]`
     * @param operator The operator who is being delegated to
     * @param expiry The desired expiry time of the staker's signature
     */
    function calculateStakerDelegationDigestHash(
        address staker,
        uint256 _stakerNonce,
        address operator,
        uint256 expiry
    ) external view returns (bytes32);

    function pendingWithdrawals(bytes32) external view returns (bool);

    /**
     * @notice Calculates the digest hash to be signed by the operator's delegationApprove and used in the `delegateTo`
     * and `delegateToBySignature` functions.
     * @param staker The account delegating their stake
     * @param operator The account receiving delegated stake
     * @param _delegationApprover the operator's `delegationApprover` who will be signing the delegationHash (in
     * general)
     * @param approverSalt A unique and single use value associated with the approver signature.
     * @param expiry Time after which the approver's signature becomes invalid
     */
    function calculateDelegationApprovalDigestHash(
        address staker,
        address operator,
        address _delegationApprover,
        bytes32 approverSalt,
        uint256 expiry
    ) external view returns (bytes32);

    /// @notice The EIP-712 typehash for the contract's domain
    function DOMAIN_TYPEHASH() external view returns (bytes32);

    /// @notice The EIP-712 typehash for the StakerDelegation struct used by the contract
    function STAKER_DELEGATION_TYPEHASH() external view returns (bytes32);

    /// @notice The EIP-712 typehash for the DelegationApproval struct used by the contract
    function DELEGATION_APPROVAL_TYPEHASH() external view returns (bytes32);

    /**
     * @notice Getter function for the current EIP-712 domain separator for this contract.
     *
     * @dev The domain separator will change in the event of a fork that changes the ChainID.
     * @dev By introducing a domain separator the DApp developers are guaranteed that there can be no signature
     * collision.
     * for more detailed information please read EIP-712.
     */
    function domainSeparator() external view returns (bytes32);

    /// @notice Mapping: staker => cumulative number of queued withdrawals they have ever initiated.
    /// @dev This only increments (doesn't decrement), and is used to help ensure that otherwise identical withdrawals
    /// have unique hashes.
    function cumulativeWithdrawalsQueued(address staker) external view returns (uint256);

    /// @notice Returns the keccak256 hash of `withdrawal`.
    function calculateWithdrawalRoot(Withdrawal memory withdrawal) external pure returns (bytes32);
}
