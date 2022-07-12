// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

/**
 * @notice A library which implements fixed point decimal math.
 */
library FixedPointMath {
  /** @dev This will give approximately 60 bits of precision */
  uint256 public constant DECIMALS = 18;
  uint256 public constant ONE = 10**DECIMALS;

  /**
   * @notice A struct representing a fixed point decimal.
   */
  struct Number {
    uint256 n;
  }

  /**
   * @notice Encodes a unsigned 256-bit integer into a fixed point decimal.
   *
   * @param value The value to encode.
   * @return      The fixed point decimal representation.
   */
  function encode(uint256 value) internal pure returns (Number memory) {
    return Number(FixedPointMath.encodeRaw(value));
  }

  /**
   * @notice Encodes a unsigned 256-bit integer into a uint256 representation of a
   *         fixed point decimal.
   *
   * @param value The value to encode.
   * @return      The fixed point decimal representation.
   */
  function encodeRaw(uint256 value) internal pure returns (uint256) {
    return value * ONE;
  }

  /**
   * @notice Encodes a uint256 MAX VALUE into a uint256 representation of a
   *         fixed point decimal.
   *
   * @return      The uint256 MAX VALUE fixed point decimal representation.
   */
  function max() internal pure returns (Number memory) {
    return Number(type(uint256).max);
  }

  /**
   * @notice Creates a rational fraction as a Number from 2 uint256 values
   *
   * @param n The numerator.
   * @param d The denominator.
   * @return  The fixed point decimal representation.
   */
  function rational(uint256 n, uint256 d) internal pure returns (Number memory) {
    Number memory numerator = encode(n);
    return FixedPointMath.div(numerator, d);
  }

  /**
   * @notice Adds two fixed point decimal numbers together.
   *
   * @param self  The left hand operand.
   * @param value The right hand operand.
   * @return      The result.
   */
  function add(Number memory self, Number memory value) internal pure returns (Number memory) {
    return Number(self.n + value.n);
  }

  /**
   * @notice Adds a fixed point number to a unsigned 256-bit integer.
   *
   * @param self  The left hand operand.
   * @param value The right hand operand. This will be converted to a fixed point decimal.
   * @return      The result.
   */
  function add(Number memory self, uint256 value) internal pure returns (Number memory) {
    return add(self, FixedPointMath.encode(value));
  }

  /**
   * @notice Subtract a fixed point decimal from another.
   *
   * @param self  The left hand operand.
   * @param value The right hand operand.
   * @return      The result.
   */
  function sub(Number memory self, Number memory value) internal pure returns (Number memory) {
    return Number(self.n - value.n);
  }

  /**
   * @notice Subtract a unsigned 256-bit integer from a fixed point decimal.
   *
   * @param self  The left hand operand.
   * @param value The right hand operand. This will be converted to a fixed point decimal.
   * @return      The result.
   */
  function sub(Number memory self, uint256 value) internal pure returns (Number memory) {
    return sub(self, FixedPointMath.encode(value));
  }

  /**
   * @notice Multiplies a fixed point decimal by another fixed point decimal.
   *
   * @param self  The fixed point decimal to multiply.
   * @param number The fixed point decimal to multiply by.
   * @return      The result.
   */
  function mul(Number memory self, Number memory number) internal pure returns (Number memory) {
    return Number((self.n * number.n) / ONE);
  }

  /**
   * @notice Multiplies a fixed point decimal by an unsigned 256-bit integer.
   *
   * @param self  The fixed point decimal to multiply.
   * @param value The unsigned 256-bit integer to multiply by.
   * @return      The result.
   */
  function mul(Number memory self, uint256 value) internal pure returns (Number memory) {
    return Number(self.n * value);
  }

  /**
   * @notice Divides a fixed point decimal by an unsigned 256-bit integer.
   *
   * @param self  The fixed point decimal to multiply by.
   * @param value The unsigned 256-bit integer to divide by.
   * @return      The result.
   */
  function div(Number memory self, uint256 value) internal pure returns (Number memory) {
    return Number(self.n / value);
  }

  /**
   * @notice Compares two fixed point decimals.
   *
   * @param self  The left hand number to compare.
   * @param value The right hand number to compare.
   * @return      When the left hand number is less than the right hand number this returns -1,
   *              when the left hand number is greater than the right hand number this returns 1,
   *              when they are equal this returns 0.
   */
  function cmp(Number memory self, Number memory value) internal pure returns (int256) {
    if (self.n < value.n) {
      return -1;
    }

    if (self.n > value.n) {
      return 1;
    }

    return 0;
  }

  /**
   * @notice Gets if two fixed point numbers are equal.
   *
   * @param self  the first fixed point number.
   * @param value the second fixed point number.
   *
   * @return if they are equal.
   */
  function equals(Number memory self, Number memory value) internal pure returns (bool) {
    return self.n == value.n;
  }

  /**
   * @notice Truncates a fixed point decimal into an unsigned 256-bit integer.
   *
   * @return The integer portion of the fixed point decimal.
   */
  function truncate(Number memory self) internal pure returns (uint256) {
    return self.n / ONE;
  }
}
