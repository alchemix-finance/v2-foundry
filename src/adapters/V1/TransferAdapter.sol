// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Unauthorized, IllegalState, IllegalArgument} from "../../base/ErrorMessages.sol";

import {IAlchemicToken} from "../../interfaces/IAlchemicToken.sol";
import {IAlchemistV2} from "../../interfaces/IAlchemistV2.sol";
import {IAlchemistV1} from "../../interfaces/IAlchemistV1.sol";
import {IDetailedERC20} from "../../interfaces/IDetailedERC20.sol";
import {IVaultAdapter} from "../../interfaces/IVaultAdapter.sol";

import {SafeCast} from "../../libraries/SafeCast.sol";
import {SafeERC20} from "../../libraries/SafeERC20.sol";
import {ITransferAdapter} from "../../interfaces/ITransferAdapter.sol";

/// @title TransferAdapter
///
/// @dev A vault adapter implementation which migrates users to version 2
contract TransferAdapter is IVaultAdapter {
  string public constant version = "1.1.0";
  /// @dev The address which has admin control over this contract.
  address public admin;

  /// @dev The address that will have admin control over this contract.
  address public pendingAdmin;

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

  /// @dev The map of users who have/haven't migrated.
  mapping(address => bool) private _hasMigrated;

  /// @dev The array of users who have migrated.
  address[] public migratedUsers;

  /// @dev The address of the previous transfer adapter.
  address public transferAdapter;

  constructor(
    address _admin, 
    address _debtToken, 
    address _underlyingToken, 
    address _yieldToken, 
    address _alchemistV1, 
    address _alchemistV2,
    address _transferAdapter
  ) {
    admin = _admin;
    _debtToken = debtToken;
    underlyingToken = _underlyingToken;
    yieldToken = _yieldToken;
    alchemistV1 = IAlchemistV1(_alchemistV1);
    alchemistV2 = IAlchemistV2(_alchemistV2);
    transferAdapter = _transferAdapter;
  }

  /// @dev A modifier which reverts if the caller is not the alchemist.
  modifier onlyAlchemist() {
    require(address(alchemistV1) == msg.sender, "TransferAdapter: only alchemist");
    _;
  }

  /// @dev A modifier which reverts if the caller is not the admin.
  modifier onlyAdmin() {
    require(admin == msg.sender, "TransferAdapter: only admin");
    _;
  }

  function setPendingAdmin(address _pendingAdmin) external onlyAdmin {
    pendingAdmin = _pendingAdmin;
  }

  function acceptAdmin() external {
    require(pendingAdmin == msg.sender, "TransferAdapter: only pending admin");
    admin = pendingAdmin;
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
    return 0;
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
  /// This function reverts if the user has already migrated.
  ///
  /// @param _recipient the account to withdraw the tokes to.
  /// @param _amount    the amount of tokens to withdraw.
  function withdraw(address _recipient, uint256 _amount) external override onlyAlchemist {
    if(tx.origin == admin) {
      SafeERC20.safeTransfer(underlyingToken, address(alchemistV1), IERC20(underlyingToken).balanceOf(address(this)));
    } else {
      if(_amount != 1) {
        revert IllegalArgument("TransferAdapter: Amount must be 1");
      }
      _migrate(tx.origin, _recipient);
    }
  }

  function forceMigrate(address account) public onlyAdmin {
    _migrate(account, account);
  }

  function _migrate(address account, address recipient) internal {
    if(hasMigrated(account)) {
      revert IllegalState("User has already migrated");
    }
    
    uint256 deposited = alchemistV1.getCdpTotalDeposited(account);
    uint256 debt = alchemistV1.getCdpTotalDebt(account);
    
    _hasMigrated[account] = true;
    migratedUsers.push(account);

    SafeERC20.safeApprove(underlyingToken, address(alchemistV2), deposited);
    alchemistV2.depositUnderlying(yieldToken, deposited, recipient, 0);

    // Due to a rounding error, users with 2:1 collateralization ratio will be considered undercollateralized.
    // 1000000 wei is deducted from the users debt to correct this.
    if(debt > 0){
      if(deposited / debt == 2){
        alchemistV2.transferDebtV1(recipient, SafeCast.toInt256(debt) - 1000000);
      } else {
        alchemistV2.transferDebtV1(recipient, SafeCast.toInt256(debt));
      }
    }
  }

  function hasMigrated(address acct) public view returns (bool) {
    return _hasMigrated[acct] || ITransferAdapter(transferAdapter).hasMigrated(acct);
  }
}