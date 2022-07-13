// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import {IllegalArgument, IllegalState, Unauthorized} from "./base/Errors.sol";

import {IERC3156FlashLender} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC3156FlashBorrower.sol";

/// @title  AlchemicTokenV2
/// @author Alchemix Finance
///
/// @notice This is the contract for version two alchemic tokens.
contract AlchemicTokenV2 is AccessControl, ReentrancyGuard, ERC20, IERC3156FlashLender {

  /// @notice The identifier of the role which maintains other roles.
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

  /// @notice The identifier of the role which allows accounts to mint tokens.
  bytes32 public constant SENTINEL_ROLE = keccak256("SENTINEL");

  /// @notice The expected return value from a flash mint receiver
  bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

  /// @notice The maximum number of basis points needed to represent 100%.
  uint256 public constant BPS = 10_000;

  /// @notice A set of addresses which are whitelisted for minting new tokens.
  mapping(address => bool) public whitelisted;

  /// @notice A set of addresses which are paused from minting new tokens.
  mapping(address => bool) public paused;

  /// @notice Fee for flash minting
  uint256 public flashMintFee;

  /// @notice Max flash mint amount
  uint256 public maxFlashLoanAmount;

  /// @notice An event which is emitted when a minter is paused from minting.
  ///
  /// @param minter The address of the minter which was paused.
  /// @param state  A flag indicating if the alchemist is paused or unpaused.
  event Paused(address minter, bool state);

  /// @notice An event which is emitted when the flash mint fee is updated.
  ///
  /// @param fee The new flash mint fee.
  event SetFlashMintFee(uint256 fee);

  /// @notice An event which is emitted when the max flash loan is updated.
  ///
  /// @param maxFlashLoan The new max flash loan.
  event SetMaxFlashLoan(uint256 maxFlashLoan);

  constructor(string memory _name, string memory _symbol, uint256 _flashFee) ERC20(_name, _symbol) {
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(SENTINEL_ROLE, msg.sender);
    _setRoleAdmin(SENTINEL_ROLE, ADMIN_ROLE);
    _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    flashMintFee = _flashFee;
    emit SetFlashMintFee(_flashFee);
  }

  /// @dev A modifier which checks that the caller has the admin role.
  modifier onlyAdmin() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      revert Unauthorized();
    }
    _;
  }

  /// @dev A modifier which checks that the caller has the sentinel role.
  modifier onlySentinel() {
    if(!hasRole(SENTINEL_ROLE, msg.sender)) {
      revert Unauthorized();
    }
    _;
  }

  /// @dev A modifier which checks if whitelisted for minting.
  modifier onlyWhitelisted() {
    if(!whitelisted[msg.sender]) {
      revert Unauthorized();
    }
    _;
  }

  /// @notice Sets the flash minting fee.
  ///
  /// @notice This function reverts if `msg.sender` is not an admin.
  ///
  /// @param newFee The new flash mint fee.
  function setFlashFee(uint256 newFee) external onlyAdmin {
    if (newFee >= BPS) {
      revert IllegalArgument();
    }
    flashMintFee = newFee;
    emit SetFlashMintFee(flashMintFee);
  }

  /// @notice Mints tokens to `a recipient.`
  ///
  /// @notice This function reverts if `msg.sender` is not whitelisted.
  /// @notice This function reverts if `msg.sender` is paused.
  ///
  /// @param recipient The address to mint the tokens to.
  /// @param amount    The amount of tokens to mint.
  function mint(address recipient, uint256 amount) external onlyWhitelisted {
    if (paused[msg.sender]) {
      revert IllegalState();
    }

    _mint(recipient, amount);
  }

  /// @notice Sets `minter` as whitelisted to mint.
  ///
  /// @notice This function reverts if `msg.sender` is not an admin.
  ///
  /// @param minter The account to permit to mint.
  /// @param state  A flag indicating if the minter should be able to mint.
  function setWhitelist(address minter, bool state) external onlyAdmin {
    whitelisted[minter] = state;
  }

  /// @notice Sets `sentinel` as a sentinel.
  ///
  /// @notice This function reverts if `msg.sender` is not an admin.
  ///
  /// @param sentinel The address to set as a sentinel.
  function setSentinel(address sentinel) external onlyAdmin {
    _setupRole(SENTINEL_ROLE, sentinel);
  }

  /// @notice Pauses `minter` from minting tokens.
  ///
  /// @notice This function reverts if `msg.sender` is not a sentinel.
  ///
  /// @param minter The address to set as paused or unpaused.
  /// @param state  A flag indicating if the minter should be paused or unpaused.
  function pauseMinter(address minter, bool state) external onlySentinel {
    paused[minter] = state;
    emit Paused(minter, state);
  }

  /// @notice Burns `amount` tokens from `msg.sender`.
  ///
  /// @param amount The amount of tokens to be burned.
  function burn(uint256 amount) external {
    _burn(msg.sender, amount);
  }

  /// @dev Destroys `amount` tokens from `account`, deducting from the caller's allowance.
  ///
  /// @param account The address the burn tokens from.
  /// @param amount  The amount of tokens to burn.
  function burnFrom(address account, uint256 amount) external {
    uint256 newAllowance = allowance(account, msg.sender) - amount;

    _approve(account, msg.sender, newAllowance);
    _burn(account, amount);
  }

  /// @notice Adjusts the maximum flashloan amount.
  ///
  /// @param _maxFlashLoanAmount The maximum flashloan amount.
  function setMaxFlashLoan(uint256 _maxFlashLoanAmount) external onlyAdmin {
    maxFlashLoanAmount = _maxFlashLoanAmount;
    emit SetMaxFlashLoan(_maxFlashLoanAmount);
  }

  /// @notice Gets the maximum amount to be flash loaned of a token.
  ///
  /// @param token The address of the token.
  ///
  /// @return The maximum amount of `token` that can be flashed loaned.
  function maxFlashLoan(address token) public view override returns (uint256) {
    if (token != address(this)) {
      return 0;
    }
    return maxFlashLoanAmount;
  }

  /// @notice Gets the flash loan fee of `amount` of `token`.
  ///
  /// @param token  The address of the token.`
  /// @param amount The amount of `token` to flash mint.
  ///
  /// @return The flash loan fee.
  function flashFee(address token, uint256 amount) public view override returns (uint256) {
    if (token != address(this)) {
      revert IllegalArgument();
    }
    return amount * flashMintFee / BPS;
  }

  /// @notice Performs a flash mint (called flash loan to confirm with ERC3156 standard).
  ///
  /// @param receiver The address which will receive the flash minted tokens.
  /// @param token    The address of the token to flash mint.
  /// @param amount   How much to flash mint.
  /// @param data     ABI encoded data to pass to the receiver.
  ///
  /// @return If the flash loan was successful.
  function flashLoan(
    IERC3156FlashBorrower receiver,
    address token,
    uint256 amount,
    bytes calldata data
  ) external override nonReentrant returns (bool) {
    if (token != address(this)) {
      revert IllegalArgument();
    }

    if (amount > maxFlashLoan(token)) {
      revert IllegalArgument();
    }

    uint256 fee = flashFee(token, amount);

    _mint(address(receiver), amount);

    if (receiver.onFlashLoan(msg.sender, token, amount, fee, data) != CALLBACK_SUCCESS) {
      revert IllegalState();
    }

    _burn(address(receiver), amount + fee); // Will throw error if not enough to burn

    return true;
  }
}
