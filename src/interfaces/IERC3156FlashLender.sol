// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import "./IERC3156FlashBorrower.sol";

/// @title IERC3156FlashLender
///
/// @dev Interface of the ERC3156 FlashLender, as defined by [ERC-3156](https://eips.ethereum.org/EIPS/eip-3156).
interface IERC3156FlashLender {
  /// @notice The amount of currency available to be lent out.
  ///
  /// @param token The loan currency.
  ///
  /// @return amount The amount of `token` that can be borrowed.
  function maxFlashLoan(address token) external view returns (uint256 amount);

  /// @notice The fee to be charged for a given loan.
  ///
  /// @param token The loan currency.
  /// @param amount The amount of tokens lent.
  ///
  /// @return fee The amount of token to be charged for the loan, on top of the returned principal.
  function flashFee(address token, uint256 amount) external view returns (uint256 fee);

  /// @notice Initiate a flash loan.
  ///
  /// @param receiver The receiver of the tokens in the loan and the receiver of the callback.
  /// @param token    The loan currency.
  /// @param amount   The amount of tokens lent.
  /// @param data     Arbitrary data structure, intended to contain user-defined parameters.
  ///
  /// @return success If the flash loan was successful.
  function flashLoan(
    IERC3156FlashBorrower receiver,
    address token,
    uint256 amount,
    bytes calldata data
  ) external returns (bool success);
}