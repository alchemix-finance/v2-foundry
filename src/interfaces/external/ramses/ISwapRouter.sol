// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title  ISwapRouter
/// @author Uniswap Labs
///
/// @notice Functions for swapping tokens via Uniswap V3.
interface ISwapRouter {

  struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
  }

  /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path.
  ///
  /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata.
  ///
  /// @return amountOut The amount of the received token
  function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

  function execute(bytes calldata commands, bytes[] calldata inputs) external;
}