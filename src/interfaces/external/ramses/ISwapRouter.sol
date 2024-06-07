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

interface ISwapRouterv2 {
  function swapExactTokensForTokens(
    uint amountIn,
    uint amountOutMin,
    route[] calldata routes,
    address to,
    uint deadline
  ) external returns (uint[] memory amounts);
}

interface V2Pool {
  function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256 amountOut);
}

interface RamsesQuote {
  function quoteExactInputSingleV3(QuoteExactInputSingleV3Params memory params)
    external
    returns (
      uint256 amountOut, 
      uint160 sqrtPriceX96After, 
      uint32 initializedTicksCrossed, 
      uint256 gasEstimate
    );
}

struct QuoteExactInputSingleV3Params {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint24 fee;
    uint160 sqrtPriceLimitX96;
}

struct route {
    address from;
    address to;
    bool stable;
}