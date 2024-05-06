// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import {AccessControlUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

import {IllegalArgument, IllegalState, Unauthorized} from "./base/Errors.sol";

import {IERC3156FlashLender} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC3156FlashBorrower.sol";

import {IXERC20} from "./interfaces/external/connext/IXERC20.sol";

/// @title  AlchemicTokenV2
/// @author Alchemix Finance
///
/// @notice This is the contract for version two alchemic tokens.
/// @notice Initially, the contract deployer is given both the admin and minter role. This allows them to pre-mine
///         tokens, transfer admin to a timelock contract, and lastly, grant the staking pools the minter role. After
///         this is done, the deployer must revoke their admin role and minter role.
contract AlchemicTokenV2Base is ERC20Upgradeable, AccessControlUpgradeable, IERC3156FlashLender, ReentrancyGuardUpgradeable {
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

  // Duration used for xERC20 rate limits
  uint256 private constant _DURATION = 1 days;
  
  ///@notice Maps bridge address to bridge configurations. Used for xERC20 compatability.
  mapping(address => IXERC20.Bridge) public xBridges;

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

  ///@notice Emits when a limit is set
  ///
  /// @param _mintingLimit The updated minting limit we are setting to the bridge
  /// @param _burningLimit The updated burning limit we are setting to the bridge
  /// @param _bridge The address of the bridge we are setting the limit too
  event BridgeLimitsSet(uint256 _mintingLimit, uint256 _burningLimit, address indexed _bridge);

  function __AlchemicTokenV2Base_init() internal {
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(SENTINEL_ROLE, msg.sender);
    _setRoleAdmin(SENTINEL_ROLE, ADMIN_ROLE);
    _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
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

    // If bridge is registered check limits and adjust them accordingly.
    if (xBridges[msg.sender].minterParams.maxLimit > 0) {
      uint256 currentLimit = mintingCurrentLimitOf(msg.sender);
      if (amount > currentLimit) revert IXERC20.IXERC20_NotHighEnoughLimits();
      _useMinterLimits(msg.sender, amount);
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
  function burnSelf(uint256 amount) external {
    // If bridge is registered check limits and update accordingly.
    if (xBridges[msg.sender].burnerParams.maxLimit > 0) {
      uint256 currentLimit = burningCurrentLimitOf(msg.sender);
      if (amount > currentLimit) revert IXERC20.IXERC20_NotHighEnoughLimits();
      _useBurnerLimits(msg.sender, amount);
    }

    _burn(msg.sender, amount);
  }

  /// @dev Destroys `amount` tokens from `account`, deducting from the caller's allowance.
  ///
  /// @param account The address the burn tokens from.
  /// @param amount  The amount of tokens to burn.
  function burn(address account, uint256 amount) external {
    if (msg.sender != account) {
      uint256 newAllowance = allowance(account, msg.sender) - amount;
      _approve(account, msg.sender, newAllowance);
    }

    // If bridge is registered check limits and update accordingly.
    if (xBridges[msg.sender].burnerParams.maxLimit > 0) {
      uint256 currentLimit = burningCurrentLimitOf(msg.sender);
      if (amount > currentLimit) revert IXERC20.IXERC20_NotHighEnoughLimits();
      _useBurnerLimits(msg.sender, amount);
    }

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

  // The following functions are a part of the connext bridge xERC20 standard

  /**
   * @notice Updates the limits of any bridge
   * @dev Can only be called by the owner
   * @param _mintingLimit The updated minting limit we are setting to the bridge
   * @param _burningLimit The updated burning limit we are setting to the bridge
   * @param _bridge The address of the bridge we are setting the limits too
   */
  function setLimits(address _bridge, uint256 _mintingLimit, uint256 _burningLimit) external onlyAdmin {
    _changeMinterLimit(_bridge, _mintingLimit);
    _changeBurnerLimit(_bridge, _burningLimit);
    emit BridgeLimitsSet(_mintingLimit, _burningLimit, _bridge);
  }

  /**
   * @notice Returns the max limit of a bridge
   *
   * @param _bridge the bridge we are viewing the limits of
   * @return _limit The limit the bridge has
   */

  function mintingMaxLimitOf(address _bridge) public view returns (uint256 _limit) {
    _limit = xBridges[_bridge].minterParams.maxLimit;
  }

  /**
   * @notice Returns the max limit of a bridge
   *
   * @param _bridge the bridge we are viewing the limits of
   * @return _limit The limit the bridge has
   */

  function burningMaxLimitOf(address _bridge) public view returns (uint256 _limit) {
    _limit = xBridges[_bridge].burnerParams.maxLimit;
  }

  /**
   * @notice Returns the current limit of a bridge
   *
   * @param _bridge the bridge we are viewing the limits of
   * @return _limit The limit the bridge has
   */

  function mintingCurrentLimitOf(address _bridge) public view returns (uint256 _limit) {
    _limit = _getCurrentLimit(
      xBridges[_bridge].minterParams.currentLimit,
      xBridges[_bridge].minterParams.maxLimit,
      xBridges[_bridge].minterParams.timestamp,
      xBridges[_bridge].minterParams.ratePerSecond
    );
  }

  /**
   * @notice Returns the current limit of a bridge
   *
   * @param _bridge the bridge we are viewing the limits of
   * @return _limit The limit the bridge has
   */

  function burningCurrentLimitOf(address _bridge) public view returns (uint256 _limit) {
    _limit = _getCurrentLimit(
      xBridges[_bridge].burnerParams.currentLimit,
      xBridges[_bridge].burnerParams.maxLimit,
      xBridges[_bridge].burnerParams.timestamp,
      xBridges[_bridge].burnerParams.ratePerSecond
    );
  }

  /**
   * @notice Uses the limit of any bridge
   * @param _bridge The address of the bridge who is being changed
   * @param _change The change in the limit
   */

  function _useMinterLimits(address _bridge, uint256 _change) internal {
    uint256 _currentLimit = mintingCurrentLimitOf(_bridge);
    xBridges[_bridge].minterParams.timestamp = block.timestamp;
    xBridges[_bridge].minterParams.currentLimit = _currentLimit - _change;
  }

  /**
   * @notice Uses the limit of any bridge
   * @param _bridge The address of the bridge who is being changed
   * @param _change The change in the limit
   */

  function _useBurnerLimits(address _bridge, uint256 _change) internal {
    uint256 _currentLimit = burningCurrentLimitOf(_bridge);
    xBridges[_bridge].burnerParams.timestamp = block.timestamp;
    xBridges[_bridge].burnerParams.currentLimit = _currentLimit - _change;
  }

  /**
   * @notice Updates the limit of any bridge
   * @dev Can only be called by the owner
   * @param _bridge The address of the bridge we are setting the limit too
   * @param _limit The updated limit we are setting to the bridge
   */

  function _changeMinterLimit(address _bridge, uint256 _limit) internal {
    uint256 _oldLimit = xBridges[_bridge].minterParams.maxLimit;
    uint256 _currentLimit = mintingCurrentLimitOf(_bridge);
    xBridges[_bridge].minterParams.maxLimit = _limit;

    xBridges[_bridge].minterParams.currentLimit = _calculateNewCurrentLimit(_limit, _oldLimit, _currentLimit);

    xBridges[_bridge].minterParams.ratePerSecond = _limit / _DURATION;
    xBridges[_bridge].minterParams.timestamp = block.timestamp;
  }

  /**
   * @notice Updates the limit of any bridge
   * @dev Can only be called by the owner
   * @param _bridge The address of the bridge we are setting the limit too
   * @param _limit The updated limit we are setting to the bridge
   */

  function _changeBurnerLimit(address _bridge, uint256 _limit) internal {
    uint256 _oldLimit = xBridges[_bridge].burnerParams.maxLimit;
    uint256 _currentLimit = burningCurrentLimitOf(_bridge);
    xBridges[_bridge].burnerParams.maxLimit = _limit;

    xBridges[_bridge].burnerParams.currentLimit = _calculateNewCurrentLimit(_limit, _oldLimit, _currentLimit);

    xBridges[_bridge].burnerParams.ratePerSecond = _limit / _DURATION;
    xBridges[_bridge].burnerParams.timestamp = block.timestamp;
  }

  /**
   * @notice Updates the current limit
   *
   * @param _limit The new limit
   * @param _oldLimit The old limit
   * @param _currentLimit The current limit
   */

  function _calculateNewCurrentLimit(
    uint256 _limit,
    uint256 _oldLimit,
    uint256 _currentLimit
  ) internal pure returns (uint256 _newCurrentLimit) {
    uint256 _difference;

    if (_oldLimit > _limit) {
      _difference = _oldLimit - _limit;
      _newCurrentLimit = _currentLimit > _difference ? _currentLimit - _difference : 0;
    } else {
      _difference = _limit - _oldLimit;
      _newCurrentLimit = _currentLimit + _difference;
    }
  }

  /**
   * @notice Gets the current limit
   *
   * @param _currentLimit The current limit
   * @param _maxLimit The max limit
   * @param _timestamp The timestamp of the last update
   * @param _ratePerSecond The rate per second
   */

  function _getCurrentLimit(
    uint256 _currentLimit,
    uint256 _maxLimit,
    uint256 _timestamp,
    uint256 _ratePerSecond
  ) internal view returns (uint256 _limit) {
    _limit = _currentLimit;
    if (_limit == _maxLimit) {
      return _limit;
    } else if (_timestamp + _DURATION <= block.timestamp) {
      _limit = _maxLimit;
    } else if (_timestamp + _DURATION > block.timestamp) {
      uint256 _timePassed = block.timestamp - _timestamp;
      uint256 _calculatedLimit = _limit + (_timePassed * _ratePerSecond);
      _limit = _calculatedLimit > _maxLimit ? _maxLimit : _calculatedLimit;
    }
  }
}