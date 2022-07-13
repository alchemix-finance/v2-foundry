// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

import "./ITransmuterV2.sol";
import "../IAlchemistV2.sol";
import "../IERC20TokenReceiver.sol";

/// @title  ITransmuterBuffer
/// @author Alchemix Finance
interface ITransmuterBuffer is IERC20TokenReceiver {
  /// @notice Parameters used to define a given weighting schema.
  ///
  /// Weighting schemas can be used to generally weight assets in relation to an action or actions that will be taken.
  /// In the TransmuterBuffer, there are 2 actions that require weighting schemas: `burnCredit` and `depositFunds`.
  ///
  /// `burnCredit` uses a weighting schema that determines which yield-tokens are targeted when burning credit from
  /// the `Account` controlled by the TransmuterBuffer, via the `Alchemist.donate` function.
  ///
  /// `depositFunds` uses a weighting schema that determines which yield-tokens are targeted when depositing
  /// underlying-tokens into the Alchemist.
  struct Weighting {
    // The weights of the tokens used by the schema.
    mapping(address => uint256) weights;
    // The tokens used by the schema.
    address[] tokens;
    // The total weight of the schema (sum of the token weights).
    uint256 totalWeight;
  }

  /// @notice Emitted when the alchemist is set.
  ///
  /// @param alchemist The address of the alchemist.
  event SetAlchemist(address alchemist);

  /// @notice Emitted when the amo is set.
  ///
  /// @param underlyingToken The address of the underlying token.
  /// @param amo             The address of the amo.
  event SetAmo(address underlyingToken, address amo);

  /// @notice Emitted when the the status of diverting to the amo is set for a given underlying token.
  ///
  /// @param underlyingToken The address of the underlying token.
  /// @param divert          Whether or not to divert funds to the amo.
  event SetDivertToAmo(address underlyingToken, bool divert);

  /// @notice Emitted when an underlying token is registered.
  ///
  /// @param underlyingToken The address of the underlying token.
  /// @param transmuter      The address of the transmuter for the underlying token.
  event RegisterAsset(address underlyingToken, address transmuter);

  /// @notice Emitted when an underlying token's flow rate is updated.
  ///
  /// @param underlyingToken The underlying token.
  /// @param flowRate        The flow rate for the underlying token.
  event SetFlowRate(address underlyingToken, uint256 flowRate);

  /// @notice Emitted when the strategies are refreshed.
  event RefreshStrategies();

  /// @notice Emitted when a source is set.
  event SetSource(address source, bool flag);

  /// @notice Emitted when a transmuter is updated.
  event SetTransmuter(address underlyingToken, address transmuter);

  /// @notice Gets the current version.
  ///
  /// @return The version.
  function version() external view returns (string memory);

  /// @notice Gets the total credit held by the TransmuterBuffer.
  ///
  /// @return The total credit.
  function getTotalCredit() external view returns (uint256);

  /// @notice Gets the total amount of underlying token that the TransmuterBuffer controls in the Alchemist.
  ///
  /// @param underlyingToken The underlying token to query.
  ///
  /// @return totalBuffered The total buffered.
  function getTotalUnderlyingBuffered(address underlyingToken) external view returns (uint256 totalBuffered);

  /// @notice Gets the total available flow for the underlying token
  ///
  /// The total available flow will be the lesser of `flowAvailable[token]` and `getTotalUnderlyingBuffered`.
  ///
  /// @param underlyingToken The underlying token to query.
  ///
  /// @return availableFlow The available flow.
  function getAvailableFlow(address underlyingToken) external view returns (uint256 availableFlow);

  /// @notice Gets the weight of the given weight type and token
  ///
  /// @param weightToken The type of weight to query.
  /// @param token       The weighted token.
  ///
  /// @return weight The weight of the token for the given weight type.
  function getWeight(address weightToken, address token) external view returns (uint256 weight);

  /// @notice Set a source of funds.
  ///
  /// @param source The target source.
  /// @param flag   The status to set for the target source.
  function setSource(address source, bool flag) external;

  /// @notice Set transmuter by admin.
  ///
  /// This function reverts if the caller is not the current admin.
  ///
  /// @param underlyingToken The target underlying token to update.
  /// @param newTransmuter   The new transmuter for the target `underlyingToken`.
  function setTransmuter(address underlyingToken, address newTransmuter) external;

  /// @notice Set alchemist by admin.
  ///
  /// This function reverts if the caller is not the current admin.
  ///
  /// @param alchemist The new alchemist whose funds we are handling.
  function setAlchemist(address alchemist) external;

  /// @notice Set the address of the amo for a target underlying token.
  ///
  /// @param underlyingToken The address of the underlying token to set.
  /// @param amo The address of the underlying token's new amo.
  function setAmo(address underlyingToken, address amo) external;

  /// @notice Set whether or not to divert funds to the amo.
  ///
  /// @param underlyingToken The address of the underlying token to set.
  /// @param divert          Whether or not to divert underlying token to the amo.
  function setDivertToAmo(address underlyingToken, bool divert) external;

  /// @notice Refresh the yield-tokens in the TransmuterBuffer.
  ///
  /// This requires a call anytime governance adds a new yield token to the alchemist.
  function refreshStrategies() external;

  /// @notice Registers an underlying-token.
  ///
  /// This function reverts if the caller is not the current admin.
  ///
  /// @param underlyingToken The underlying-token being registered.
  /// @param transmuter      The transmuter for the underlying-token.
  function registerAsset(address underlyingToken, address transmuter) external;

  /// @notice Set flow rate of an underlying token.
  ///
  /// This function reverts if the caller is not the current admin.
  ///
  /// @param underlyingToken The underlying-token getting the flow rate set.
  /// @param flowRate        The new flow rate.
  function setFlowRate(address underlyingToken, uint256 flowRate) external;

  /// @notice Sets up a weighting schema.
  ///
  /// @param weightToken The name of the weighting schema.
  /// @param tokens      The yield-tokens to weight.
  /// @param weights     The weights of the yield tokens.
  function setWeights(address weightToken, address[] memory tokens, uint256[] memory weights) external;

  /// @notice Exchanges any available flow into the Transmuter.
  ///
  /// This function is a way for the keeper to force funds to be exchanged into the Transmuter.
  ///
  /// This function will revert if called by any account that is not a keeper. If there is not enough local balance of
  /// `underlyingToken` held by the TransmuterBuffer any additional funds will be withdrawn from the Alchemist by
  /// unwrapping `yieldToken`.
  ///
  /// @param underlyingToken The address of the underlying token to exchange.
  function exchange(address underlyingToken) external;

  /// @notice Flushes funds to the amo.
  ///
  /// @param underlyingToken The underlying token to flush.
  /// @param amount          The amount to flush.
  function flushToAmo(address underlyingToken, uint256 amount) external;

  /// @notice Burns available credit in the alchemist.
  function burnCredit() external;

  /// @notice Deposits local collateral into the alchemist
  ///
  /// @param underlyingToken The collateral to deposit.
  /// @param amount          The amount to deposit.
  function depositFunds(address underlyingToken, uint256 amount) external;

  /// @notice Withdraws collateral from the alchemist
  ///
  /// This function reverts if:
  /// - The caller is not the transmuter.
  /// - There is not enough flow available to fulfill the request.
  /// - There is not enough underlying collateral in the alchemist controlled by the buffer to fulfil the request.
  ///
  /// @param underlyingToken The underlying token to withdraw.
  /// @param amount          The amount to withdraw.
  /// @param recipient       The account receiving the withdrawn funds.
  function withdraw(
    address underlyingToken,
    uint256 amount,
    address recipient
  ) external;

  /// @notice Withdraws collateral from the alchemist
  ///
  /// @param yieldToken       The yield token to withdraw.
  /// @param shares           The amount of Alchemist shares to withdraw.
  /// @param minimumAmountOut The minimum amount of underlying tokens needed to be received as a result of unwrapping the yield tokens.
  function withdrawFromAlchemist(
    address yieldToken,
    uint256 shares,
    uint256 minimumAmountOut
  ) external;
}
