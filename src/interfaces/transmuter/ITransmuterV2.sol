// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.5.0;

/// @title ITransmuterV2
/// @author Alchemix Finance
interface ITransmuterV2 {
  /// @notice Emitted when the admin address is updated.
  ///
  /// @param admin The new admin address.
  event AdminUpdated(address admin);

  /// @notice Emitted when the pending admin address is updated.
  ///
  /// @param pendingAdmin The new pending admin address.
  event PendingAdminUpdated(address pendingAdmin);

  /// @notice Emitted when the system is paused or unpaused.
  ///
  /// @param flag `true` if the system has been paused, `false` otherwise.
  event Paused(bool flag);

  /// @dev Emitted when a deposit is performed.
  ///
  /// @param sender The address of the depositor.
  /// @param owner  The address of the account that received the deposit.
  /// @param amount The amount of tokens deposited.
  event Deposit(
    address indexed sender,
    address indexed owner,
    uint256 amount
  );

  /// @dev Emitted when a withdraw is performed.
  ///
  /// @param sender    The address of the `msg.sender` executing the withdraw.
  /// @param recipient The address of the account that received the withdrawn tokens.
  /// @param amount    The amount of tokens withdrawn.
  event Withdraw(
    address indexed sender,
    address indexed recipient,
    uint256 amount
  );

  /// @dev Emitted when a claim is performed.
  ///
  /// @param sender    The address of the claimer / account owner.
  /// @param recipient The address of the account that received the claimed tokens.
  /// @param amount    The amount of tokens claimed.
  event Claim(
    address indexed sender,
    address indexed recipient,
    uint256 amount
  );

  /// @dev Emitted when an exchange is performed.
  ///
  /// @param sender The address that called `exchange()`.
  /// @param amount The amount of tokens exchanged.
  event Exchange(
    address indexed sender,
    uint256 amount
  );

  /// @dev Emitted when a collateral source is set.
  ///
  /// @param newCollateralSource The new collateral source.
  event SetNewCollateralSource(
    address newCollateralSource
  );

  /// @notice Gets the version.
  ///
  /// @return The version.
  function version() external view returns (string memory);

  /// @dev Gets the supported underlying token.
  ///
  /// @return The underlying token.
  function underlyingToken() external view returns (address);

  /// @notice Gets the address of the whitelist contract.
  ///
  /// @return whitelist The address of the whitelist contract.
  function whitelist() external view returns (address whitelist);

  /// @dev Gets the unexchanged balance of an account.
  ///
  /// @param owner The address of the account owner.
  ///
  /// @return The unexchanged balance.
  function getUnexchangedBalance(address owner) external view returns (uint256);

  /// @dev Gets the exchanged balance of an account, in units of `debtToken`.
  ///
  /// @param owner The address of the account owner.
  ///
  /// @return The exchanged balance.
  function getExchangedBalance(address owner) external view returns (uint256);

  /// @dev Gets the claimable balance of an account, in units of `underlyingToken`.
  ///
  /// @param owner The address of the account owner.
  ///
  /// @return The claimable balance.
  function getClaimableBalance(address owner) external view returns (uint256);

  /// @dev The conversion factor used to convert between underlying token amounts and debt token amounts.
  ///
  /// @return The conversion factor.
  function conversionFactor() external view returns (uint256);

  /// @dev Deposits tokens to be exchanged into an account.
  ///
  /// @param amount The amount of tokens to deposit.
  /// @param owner  The owner of the account to deposit the tokens into.
  function deposit(uint256 amount, address owner) external;

  /// @dev Withdraws tokens from the caller's account that were previously deposited to be exchanged.
  ///
  /// @param amount    The amount of tokens to withdraw.
  /// @param recipient The address which will receive the withdrawn tokens.
  function withdraw(uint256 amount, address recipient) external;

  /// @dev Claims exchanged tokens.
  ///
  /// @param amount    The amount of tokens to claim.
  /// @param recipient The address which will receive the claimed tokens.
  function claim(uint256 amount, address recipient) external;

  /// @dev Exchanges `amount` underlying tokens for `amount` synthetic tokens staked in the system.
  ///
  /// @param amount The amount of tokens to exchange.
  function exchange(uint256 amount) external;
}
