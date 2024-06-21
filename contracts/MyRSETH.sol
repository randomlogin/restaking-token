// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import {UtilLib} from "./utils/UtilLib.sol";
import {LRTConfigRoleChecker, ILRTConfig, LRTConstants} from "./utils/LRTConfigRoleChecker.sol";

import {ILRTDepositPool} from "./interfaces/ILRTDepositPool.sol";

import {ERC20Upgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

//TODO
//Implement correct transfers/allowances/totalSupply.

/// @title MyRSETH token Contract
/// @notice We expect that stETH totalSupply is nonzero, so there is at least a single holder of stETH
contract MyRSETH is Initializable, LRTConfigRoleChecker, ERC20Upgradeable, PausableUpgradeable {
    ILRTDepositPool public LRTDepositPool;
    address public STETH;
    /// @custom:oz-upgrades-unsafe-allow constructor

    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param admin Admin address
    /// @param lrtConfigAddr LRT config address
    function initialize(address admin, address lrtConfigAddr) external initializer {
        UtilLib.checkNonZeroAddress(admin);
        UtilLib.checkNonZeroAddress(lrtConfigAddr);

        __ERC20_init("MyRSETH", "MyRSETH");
        __Pausable_init();
        lrtConfig = ILRTConfig(lrtConfigAddr);

        STETH = lrtConfig.tokenMap(LRTConstants.ST_ETH_TOKEN);
        LRTDepositPool = ILRTDepositPool(lrtConfig.getContract(LRTConstants.LRT_DEPOSIT_POOL));
        emit UpdatedLRTConfig(lrtConfigAddr);
    }

    /// @notice Mints MyrsETH when called by an authorized caller
    /// @dev note that it mints `shares`, not tokens
    /// @param to the account to mint to
    /// @param amount the amount of MyRSETH shares to mint
    function mint(address to, uint256 amount) external onlyRole(LRTConstants.MINTER_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    /// @notice Burns MyRSETH when called by an authorized caller
    /// @dev note that it burns `shares`, not tokens
    /// @param account the account to burn from
    /// @param amount the amount of MyRSETH shares to burn
    function burnFrom(address account, uint256 amount) external onlyRole(LRTConstants.BURNER_ROLE) whenNotPaused {
        _burn(account, amount);
    }

    /// @dev Triggers stopped state.
    /// @dev Only callable by LRT config manager. Contract must NOT be paused.
    function pause() external onlyLRTManager {
        _pause();
    }

    /// @notice Returns to normal state.
    /// @dev Only callable by the MyRSETH admin. Contract must be paused
    function unpause() external onlyLRTAdmin {
        _unpause();
    }

    /// @notice Returns the balance of a user with the rewards from liquid staking.
    /// @param user address of the user
    function balanceOf(address user) public view override returns (uint256) {
        if (totalShares() == 0) {
            return 0;
        }
        uint256 totalAssets = LRTDepositPool.getTotalAssetDeposits(STETH);
        return shares(user) * totalAssets / totalShares();
    }

    /// @notice Returns the total supply with the rewards from liquid staking.
    function totalSupply() public view override returns (uint256) {
        return LRTDepositPool.getTotalAssetDeposits(STETH);
    }

    /// @notice Returns total amount of "internal" shares
    function totalShares() public view returns (uint256) {
        return super.totalSupply();
    }

    /// @notice Returns "internal" shares of a user
    /// @param user address of a user
    function shares(address user) public view returns (uint256) {
        return super.balanceOf(user);
    }

    /// @notice Helper function to calculate stETH into MyRSETH.
    /// @param tokens amount of tokens to be translated into shares
    /// @dev totalAssets is thought to be nonzero when totalSupply is nonzero
    function tokensToShares(uint256 tokens) public view returns (uint256) {
        if (totalShares() == 0) {
            return tokens;
        }
        uint256 totalAssets = LRTDepositPool.getTotalAssetDeposits(STETH);
        return tokens * totalShares() / totalAssets;
    }

    /// @notice Helper function to calculate MyRSETH into stETH.
    /// @param _shares amount of shares to be translated into tokens
    function sharesToTokens(uint256 _shares) public view returns (uint256) {
        if (totalShares() == 0) {
            return _shares;
        }
        uint256 totalAssets = LRTDepositPool.getTotalAssetDeposits(STETH);
        return _shares * totalAssets / totalShares();
    }
}
