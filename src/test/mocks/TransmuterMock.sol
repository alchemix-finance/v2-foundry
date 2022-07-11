// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "../../../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {ReentrancyGuard} from "../../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {ITransmuterBuffer} from "../../interfaces/transmuter/ITransmuterBuffer.sol";

contract TransmuterMock is Context, ReentrancyGuard {
  using SafeERC20 for IERC20Upgradeable;

  address public constant ZERO_ADDRESS = address(0);
  uint256 public TRANSMUTATION_PERIOD;

  address public alToken;
  address public underlyingToken;

  uint256 public totalExchanged;

  address public collateralSource;

  /// @dev alchemist addresses whitelisted
  mapping(address => bool) public whiteList;

  /// @dev The address of the account which currently has administrative capabilities over this contract.
  address public governance;

  event Distribution(address origin, address underlying, uint256 amount);

  event WhitelistSet(address whitelisted, bool state);

  constructor(
    address _alToken,
    address _underlyingToken,
    address _collateralSource
  ) {
    governance = msg.sender;
    alToken = _alToken;
    underlyingToken = _underlyingToken;
    collateralSource = _collateralSource;
    TRANSMUTATION_PERIOD = 50;
  }

  /// @dev A modifier which checks if whitelisted for minting.
  modifier onlyWhitelisted() {
    require(whiteList[msg.sender], "Transmuter: !whitelisted");
    _;
  }

  /// @dev Checks that the current message sender or caller is the governance address.
  ///
  ///
  modifier onlyGov() {
    require(msg.sender == governance, "Transmuter: !governance");
    _;
  }

  /// @dev Sets the whitelist
  ///
  /// This function reverts if the caller is not governance
  ///
  /// @param _toWhitelist the account to mint underlyingTokens to.
  /// @param _state the whitelist state.
  function setWhitelist(address _toWhitelist, bool _state) external onlyGov {
    whiteList[_toWhitelist] = _state;
    emit WhitelistSet(_toWhitelist, _state);
  }

  function exchange(uint256 amount) external {
    totalExchanged += amount;
  }

  function claim(
    uint256 amount,
    address recipient
  ) external {
    ITransmuterBuffer(collateralSource).withdraw(underlyingToken, amount, recipient);
  }
}
