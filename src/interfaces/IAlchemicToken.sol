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

  function setWhitelist(address _toWhitelist, bool _state) external;
}