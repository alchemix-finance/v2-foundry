pragma solidity ^0.8.11;

/// @title  CodehashWhitelist
/// @author Alchemix Finance
interface ICodehashWhitelist {
  /// @dev Emitted when a codehash is added to the whitelist.
  ///
  /// @param codehash The codehash that was added to the whitelist.
  event CodehashAdded(bytes32 codehash);

  /// @dev Emitted when a codehash is removed from the whitelist.
  ///
  /// @param codehash The codehash that was removed from the whitelist.
  event CodehashRemoved(bytes32 codehash);

  /// @dev Emitted when the whitelist is deactivated.
  event WhitelistDisabled();

  /// @dev Returns the list of codehashes that are whitelisted for the given contract address.
  ///
  /// @return codehashes The codehashes that are whitelisted to interact with the given contract.
  function getCodehashes() external view returns (bytes32[] memory codehashes);

  /// @dev Returns the disabled status of a given whitelist.
  ///
  /// @return disabled A flag denoting if the given whitelist is disabled.
  function disabled() external view returns (bool);

  /// @dev Adds an contract to the whitelist.
  ///
  /// @param codehash The bytes32 to add to the whitelist.
  function add(bytes32 codehash) external;

  /// @dev Adds a contract to the whitelist.
  ///
  /// @param codehash The bytes32 to remove from the whitelist.
  function remove(bytes32 codehash) external;

  /// @dev Disables the whitelist of the target whitelisted contract.
  ///
  /// This can only occur once. Once the whitelist is disabled, then it cannot be reenabled.
  function disable() external;

  /// @dev Checks that the `msg.sender` is whitelisted when it is not an EOA.
  ///
  /// @param account The account to check.
  ///
  /// @return whitelisted A flag denoting if the given account is whitelisted.
  function isWhitelisted(address account) external view returns (bool);
}
