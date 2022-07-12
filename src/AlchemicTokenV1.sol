// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  AlchemicTokenV1
/// @author Alchemix Finance
///
/// @notice This is the contract for version one alchemic tokens.
contract AlchemicTokenV1 is AccessControl, ERC20("Alchemix USD", "alUSD") {
  using SafeERC20 for ERC20;

  /// @notice An event which is emitted when a minter is paused or unpaused.
  ///
  /// @param minter The address of the minter.
  /// @param state  A flag indicating if the minter is paused or unpaused.
  event Paused(address minter, bool state);

  /// @notice The identifier of the role which maintains other roles.
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

  /// @notice The identifier of the role which allows accounts to mint tokens.
  bytes32 public constant SENTINEL_ROLE = keccak256("SENTINEL");
  
  /// @notice A set of addresses which are whitelisted for minting new tokens.
  mapping (address => bool) public whiteList;
  
  /// @notice A set of addresses which are blacklisted from minting new tokens.
  mapping (address => bool) public blacklist;

  /// @notice A set of addresses which are paused from minting new tokens.
  mapping (address => bool) public paused;

  /// @notice The amount that each address is permitted to mint.
  mapping (address => uint256) public ceiling;

  /// @notice The amount of tokens that each address has already minted.
  mapping (address => uint256) public hasMinted;
  
  constructor() {
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(SENTINEL_ROLE, msg.sender);
    _setRoleAdmin(SENTINEL_ROLE, ADMIN_ROLE);
    _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
  }

  /// @dev A modifier which checks if whitelisted for minting.
  modifier onlyWhitelisted() {
    require(whiteList[msg.sender], "AlTokenV1: Alchemist is not whitelisted");
    _;
  }

  /// @dev A modifier which checks that `msg.sender` is an admin.
  modifier onlyAdmin() {
    require(hasRole(ADMIN_ROLE, msg.sender), "AlTokenV1: Only admin");
    _;
  }

  /// @dev A modifier which checks that `msg.sender` is a sentinel.
  modifier onlySentinel() {
    require(hasRole(SENTINEL_ROLE, msg.sender), "AlTokenV1: Only sentinel");
    _;
  }

  /// @notice Mints tokens to `recipient`.
  ///
  /// @notice This function reverts if `msg.sender` is not whitelisted.
  /// @notice This function reverts if `msg.sender` is blacklisted.
  /// @notice This function reverts if `msg.sender` is paused.
  /// @notice This function reverts if `msg.sender` has exceeded their mintable ceiling.
  ///
  /// @param recipient The address to mint the tokens to.
  /// @param amount    The amount of tokens to mint.
  function mint(address recipient, uint256 amount) external onlyWhitelisted {
    require(!blacklist[msg.sender], "AlUSD: Alchemist is blacklisted.");
    require(!paused[msg.sender], "AlUSD: Currently paused.");

    uint256 total = amount + hasMinted[msg.sender];
    require(total <= ceiling[msg.sender], "AlUSD: Alchemist's ceiling was breached.");
    hasMinted[msg.sender] = hasMinted[msg.sender] + amount;
    _mint(recipient, amount);
  }

  /// @notice Sets `minter` as whitelisted to mint.
  ///
  /// @notice This function reverts if `msg.sender` is not an admin.
  ///
  /// @param minter The account to permit to mint.
  /// @param state  A flag indicating if the minter should be able to mint.
  function setWhitelist(address minter, bool state) external onlyAdmin {
    whiteList[minter] = state;
  }

  /// @notice Sets `sentinel` as a sentinel.
  ///
  /// @notice This function reverts if `msg.sender` is not an admin.
  ///
  /// @param sentinel The address to set as a sentinel.
  function setSentinel(address sentinel) external onlyAdmin {
    _setupRole(SENTINEL_ROLE, sentinel);
  }

  /// @notice Sets `minter` as blacklisted from minting.
  ///
  /// @notice This function reverts if `msg.sender` is not a sentinel.
  ///
  /// @param minter The address to blacklist.
  function setBlacklist(address minter) external onlySentinel {
    blacklist[minter] = true;
  }

  /// @notice Pauses an alchemist from minting.
  ///
  /// @notice This function reverts if `msg.sender` is not a sentinel.
  ///
  /// @param alchemist The address of the alchemist to set as paused or unpaused.
  /// @param state     A flag indicating if the alchemist should be paused or unpaused.
  function pauseAlchemist(address alchemist, bool state) external onlySentinel {
    paused[alchemist] = state;
    emit Paused(alchemist, state);
  }

  /// @notice Sets the maximum amount of tokens that `minter` is allowed to mint.
  ///
  /// @notice This function reverts if `msg.sender` is not an admin.
  ///
  /// @param minter  The address of the minter.
  /// @param maximum The maximum amount of tokens that the minter is allowed to mint.
  function setCeiling(address minter, uint256 maximum) external onlyAdmin {
    ceiling[minter] = maximum;
  }

  /// @notice Burns `amount` tokens from `msg.sender`
  ///
  /// @param amount The amount of tokens to burn.
  function burn(uint256 amount) public {
      _burn(msg.sender, amount);
  }

  /// @notice Burns `amount` tokens from `owner`.
  ///
  /// @notice Reverts if the allowance of `msg.sender` is less than `amount`.
  ///
  /// @param owner  The address which owns the tokens to burn.
  /// @param amount The amount of tokens to burn.
  function burnFrom(address owner, uint256 amount) public {
      uint256 decreasedAllowance = allowance(owner, msg.sender) - amount;
      _approve(owner, msg.sender, decreasedAllowance);
      _burn(owner, amount);
  }

  /// @notice Lowers the number of tokens which the `msg.sender` has minted.
  ///
  /// @notice This reverts if the `msg.sender` is not whitelisted.
  ///
  /// @param amount The amount to lower the minted amount by.
  function lowerHasMinted(uint256 amount) public onlyWhitelisted {
      hasMinted[msg.sender] = hasMinted[msg.sender] - amount;
  }
}