// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

import { IllegalArgument } from "../base/Errors.sol";

import { FixedPointMath } from "./FixedPointMath.sol";

/// @title  LiquidityMath
/// @author Alchemix Finance
library LiquidityMath {
  using FixedPointMath for FixedPointMath.Number;

  uint256 constant PRECISION = 1e18;

  /// @dev Adds a signed delta to an unsigned integer.
  ///
  /// @param  x The unsigned value to add the delta to.
  /// @param  y The signed delta value to add.
  /// @return z The result.
  function addDelta(uint256 x, int256 y) internal pure returns (uint256 z) {
    if (y < 0) {
      if ((z = x - uint256(-y)) >= x) {
        revert IllegalArgument();
      }
    } else {
      if ((z = x + uint256(y)) < x) {
        revert IllegalArgument();
      }
    }
  }

  /// @dev Calculate a uint256 representation of x * y using FixedPointMath
  ///
  /// @param  x The first factor
  /// @param  y The second factor (fixed point)
  /// @return z The resulting product, after truncation
  function calculateProduct(uint256 x, FixedPointMath.Number memory y) internal pure returns (uint256 z) {
    z = y.mul(x).truncate();
  }

  /// @notice normalises non 18 digit token values to 18 digits.
  function normalizeValue(uint256 input, uint256 decimals) internal pure returns (uint256) {
    return (input * PRECISION) / (10**decimals);
  }

  /// @notice denormalizes 18 digits back to a token's digits
  function deNormalizeValue(uint256 input, uint256 decimals) internal pure returns (uint256) {
    return (input * (10**decimals)) / PRECISION;
  }
}
