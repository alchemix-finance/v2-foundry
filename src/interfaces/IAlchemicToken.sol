// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title  IAlchemicToken
/// @author Alchemix Finance
interface IAlchemicToken is IERC20 {
  /// @notice Gets the total amount of minted tokens for an account.
  ///
  /// @param account The address of the account.
  ///
  /// @return The total minted.
  function hasMinted(address account) external view returns (uint256);

  /// @notice Lowers the number of tokens which the `msg.sender` has minted.
  ///
  /// This reverts if the `msg.sender` is not whitelisted.
  ///
  /// @param amount The amount to lower the minted amount by.
  function lowerHasMinted(uint256 amount) external;

  /// @notice Sets the mint allowance for a given account'
  ///
  /// This reverts if the `msg.sender` is not admin
  ///
  /// @param toSetCeiling The account whos allowance to update
  /// @param ceiling      The amount of tokens allowed to mint
  function setCeiling(address toSetCeiling, uint256 ceiling) external;

  /// @notice Updates the state of an address in the whitelist map
  ///
  /// This reverts if msg.sender is not admin
  ///
  /// @param toWhitelist the address whos state is being updated
  /// @param state the boolean state of the whitelist
  function setWhitelist(address toWhitelist, bool state) external;

  function mint(address recipient, uint256 amount) external;

  function burn(uint256 amount) external;
}