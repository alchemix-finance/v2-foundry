pragma solidity ^0.8.13;

import "../base/Errors.sol";
import "../interfaces/IWhitelist.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../libraries/Sets.sol";

/// @title  Whitelist
/// @author Alchemix Finance
contract Whitelist is IWhitelist, Ownable {
  using Sets for Sets.AddressSet;
  Sets.AddressSet addresses;

  /// @inheritdoc IWhitelist
  bool public override disabled;

  constructor() Ownable() {}

  /// @inheritdoc IWhitelist
  function getAddresses() external view returns (address[] memory) {
    return addresses.values;
  }

  /// @inheritdoc IWhitelist
  function add(address caller) external override {
    _onlyAdmin();
    if (disabled) {
      revert IllegalState();
    }
    addresses.add(caller);
    emit AccountAdded(caller);
  }

  /// @inheritdoc IWhitelist
  function remove(address caller) external override {
    _onlyAdmin();
    if (disabled) {
      revert IllegalState();
    }
    addresses.remove(caller);
    emit AccountRemoved(caller);
  }

  /// @inheritdoc IWhitelist
  function disable() external override {
    _onlyAdmin();
    disabled = true;
    emit WhitelistDisabled();
  }

  /// @inheritdoc IWhitelist
  function isWhitelisted(address account) external view override returns (bool) {
    return disabled || addresses.contains(account);
  }

  /// @dev Reverts if the caller is not the contract owner.
  function _onlyAdmin() internal view {
    if (msg.sender != owner()) {
      revert Unauthorized();
    }
  }
}
