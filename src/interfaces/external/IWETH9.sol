pragma solidity >=0.5.0;

import "../IERC20Minimal.sol";
import "../IERC20Metadata.sol";

/// @title IWETH9
interface IWETH9 is IERC20Minimal, IERC20Metadata {
  /// @notice Deposits `msg.value` ethereum into the contract and mints `msg.value` tokens.
  function deposit() external payable;

  /// @notice Burns `amount` tokens to retrieve `amount` ethereum from the contract.
  ///
  /// @dev This version of WETH utilizes the `transfer` function which hard codes the amount of gas
  ///      that is allowed to be utilized to be exactly 2300 when receiving ethereum.
  ///
  /// @param amount The amount of tokens to burn.
  function withdraw(uint256 amount) external;
}