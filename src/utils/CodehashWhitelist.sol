pragma solidity ^0.8.11;

import "../base/Errors.sol";
import "../interfaces/ICodehashWhitelist.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title  Whitelist
/// @author Alchemix Finance
contract CodehashWhitelist is ICodehashWhitelist, Ownable {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  EnumerableSet.Bytes32Set codehashes;

  /// @inheritdoc ICodehashWhitelist
  bool public override disabled;

  constructor() Ownable() {}

  /// @inheritdoc ICodehashWhitelist
  function getCodehashes() external view returns (bytes32[] memory) {
    return codehashes.values();
  }

  /// @inheritdoc ICodehashWhitelist
  function add(address account) external override {
    _onlyAdmin();
    if (disabled) {
      revert IllegalState();
    }
    codehashes.add(account.codehash);
    emit CodehashAdded(account.codehash);
  }

  /// @inheritdoc ICodehashWhitelist
  function remove(bytes32 codehash) external override {
    _onlyAdmin();
    if (disabled) {
      revert IllegalState();
    }
    codehashes.remove(codehash);
    emit CodehashRemoved(codehash);
  }

  /// @inheritdoc ICodehashWhitelist
  function disable() external override {
    _onlyAdmin();
    disabled = true;
    emit WhitelistDisabled();
  }

  /// @inheritdoc ICodehashWhitelist
  function isWhitelisted(address account) external view override returns (bool) {
    return disabled || codehashes.contains(account.codehash);
  }

  /// @dev Reverts if the caller is not the contract owner.
  function _onlyAdmin() internal view {
    if (msg.sender != owner()) {
      revert Unauthorized();
    }
  }
}
