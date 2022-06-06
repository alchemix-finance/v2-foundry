// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import {IAlchemicToken} from "../../interfaces/IAlchemicToken.sol";
import {IAlchemistV2} from "../../interfaces/IAlchemistV2.sol";
import {IAlchemistV1} from "../../interfaces/IAlchemistV1.sol";
import {IDetailedERC20} from "../../interfaces/IDetailedERC20.sol";
import {IVaultAdapter} from "../../interfaces/IVaultAdapter.sol";

import {SafeERC20} from "../../libraries/SafeERC20.sol";

/// @title TransferAdapter
///
/// @dev A vault adapter implementation which migrates users to version 2
contract TransferAdapter is IVaultAdapter {
  /// @dev The address which has admin control over this contract.
  address public admin;

    /// @dev The address of the debt token.
  address public debtToken;

  /// @dev The underlyingToken address.
  address public underlyingToken;

  /// @dev The yieldToken address.
  address public yieldToken;

  /// @dev The alchemistV1.
  IAlchemistV1 public alchemistV1;

  /// @dev The alchemistV2.
  IAlchemistV2 public alchemistV2;

  /// @dev The ap of users who have/haven't migrated.
  mapping(address => bool) private _hasMigrated;


  constructor(address _admin, address _debtToken, address _underlyingToken, address _yieldToken, address _alchemistV1, address _alchemistV2) {
    admin = _admin;
    _debtToken = debtToken;
    underlyingToken = _underlyingToken;
    yieldToken = _yieldToken;
    alchemistV1 = IAlchemistV1(_alchemistV1);
    alchemistV2 = IAlchemistV2(_alchemistV2);
  }

  /// @dev A modifier which reverts if the caller is not the admin.
  modifier onlyAdmin() {
    require(admin == msg.sender, "TransferAdapter: only admin");
    _;
  }

  /// @dev Gets the token that the vault accepts.
  ///
  /// @return the accepted token.
  function token() external view override returns (IDetailedERC20) {
    return IDetailedERC20(underlyingToken);
  }

  /// @dev Gets the total value of the assets that the adapter holds.
  ///
  /// @return the total assets.
  function totalValue() external view override returns (uint256) {
    return IDetailedERC20(underlyingToken).balanceOf(address(this));
  }

  /// @dev Deposits tokens into the vault.
  ///
  /// @param _amount the amount of tokens to deposit into the vault.
  function deposit(uint256 _amount) external override {
      // Accept tokens from alchemist
  }

  /// @dev Withdraws tokens from the vault to the recipient.
  ///
  /// This function reverts if the caller is not the admin.
  ///
  /// @param _recipient the account to withdraw the tokes to.
  /// @param _amount    the amount of tokens to withdraw.
  function withdraw(address _recipient, uint256 _amount) external override onlyAdmin {
    require(_amount == 1, "TransferAdapter: Amount must be 1");
    require(_hasMigrated[tx.origin] == false, "User has already migrated");

    uint256 deposited = alchemistV1.getCdpTotalDeposited(tx.origin);
    uint256 debt = alchemistV1.getCdpTotalDebt(tx.origin);

    SafeERC20.safeApprove(underlyingToken, address(alchemistV2), deposited);
    alchemistV2.depositUnderlying(yieldToken, deposited, _recipient, 0);

    _hasMigrated[tx.origin] = true;

    alchemistV2.transferDebtV1(_recipient, int256(debt));
  }
}