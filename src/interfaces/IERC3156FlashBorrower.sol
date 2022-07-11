// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title IERC3156FlashBorrower
///
/// @dev Interface of the ERC3156 FlashBorrower, as defined by [ERC-3156](https://eips.ethereum.org/EIPS/eip-3156).
interface IERC3156FlashBorrower {
  /// @notice Receive a flash loan.
  ///
  /// @param initiator The initiator of the loan.
  /// @param token     The loan currency.
  /// @param amount    The amount of tokens lent.
  /// @param fee       The additional amount of tokens to repay.
  /// @param data      Arbitrary data structure, intended to contain user-defined parameters.
  ///
  /// @return magic The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
  function onFlashLoan(
    address initiator,
    address token,
    uint256 amount,
    uint256 fee,
    bytes calldata data
  ) external returns (bytes32 magic);
}