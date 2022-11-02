// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.5.0;

import {IERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAToken} from "./IAToken.sol";
import {ILendingPool} from "./ILendingPool.sol";

/// @title  IStaticAToken
/// @author Aave
///
/// @dev Wrapper token that allows to deposit tokens on the Aave protocol and receive token which balance doesn't
///      increase automatically, but uses an ever-increasing exchange rate. Only supporting deposits and withdrawals.
interface IStaticAToken is IERC20 {
  struct SignatureParams {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  function LENDING_POOL() external returns (ILendingPool);
  function ATOKEN() external view returns (IERC20);
  function ASSET() external returns (IERC20);

  function _nonces(address owner) external returns (uint256);

  function claimRewards() external;

  function deposit(
    address recipient,
    uint256 amount,
    uint16 referralCode,
    bool fromUnderlying
  ) external returns (uint256);

  function withdraw(
    address recipient,
    uint256 amount,
    bool toUnderlying
  ) external returns (uint256, uint256);

  function withdrawDynamicAmount(
    address recipient,
    uint256 amount,
    bool toUnderlying
  ) external returns (uint256, uint256);

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s,
    uint256 chainId
  ) external;

  function metaDeposit(
    address depositor,
    address recipient,
    uint256 value,
    uint16 referralCode,
    bool fromUnderlying,
    uint256 deadline,
    SignatureParams calldata sigParams,
    uint256 chainId
  ) external returns (uint256);

  function metaWithdraw(
    address owner,
    address recipient,
    uint256 staticAmount,
    uint256 dynamicAmount,
    bool toUnderlying,
    uint256 deadline,
    SignatureParams calldata sigParams,
    uint256 chainId
  ) external returns (uint256, uint256);

  function dynamicBalanceOf(address account) external view returns (uint256);

  /// @dev Converts a static amount (scaled balance on aToken) to the aToken/underlying value, using the current
  ///      liquidity index on Aave.
  ///
  /// @param amount The amount to convert from.
  ///
  /// @return dynamicAmount The dynamic amount.
  function staticToDynamicAmount(uint256 amount) external view returns (uint256 dynamicAmount);

  /// @dev Converts an aToken or underlying amount to the what it is denominated on the aToken as scaled balance,
  ///      function of the principal and the liquidity index.
  ///
  /// @param amount The amount to convert from.
  ///
  /// @return staticAmount The static (scaled) amount.
  function dynamicToStaticAmount(uint256 amount) external view returns (uint256 staticAmount);

  /// @dev Returns the Aave liquidity index of the underlying aToken, denominated rate here as it can be considered as
  ///      an ever-increasing exchange rate.
  ///
  /// @return The rate.
  function rate() external view returns (uint256);

  /// @dev Function to return a dynamic domain separator, in order to be compatible with forks changing chainId.
  ///
  /// @param chainId The chain id.
  ///
  /// @return The domain separator.
  function getDomainSeparator(uint256 chainId) external returns (bytes32);
}