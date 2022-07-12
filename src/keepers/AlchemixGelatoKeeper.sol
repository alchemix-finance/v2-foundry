pragma solidity ^0.8.13;

import { Ownable } from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract AlchemixGelatoKeeper is Ownable {
  /// @notice Thrown when the gas price set on the tx is greater than the `maxGasPrice`.
  error TheGasIsTooDamnHigh();
  /// @notice Thrown when any address but the `gelatoPoker` attempts to call the upkeep function.
  error Unauthorized();

  /// @notice Emitted when the `gelatoPoker` address is updated.
  ///
  /// @param newPoker The new address of the `gelatoPoker`.
  event SetPoker(address newPoker);

  /// @notice Emitted when the `maxGasPrice` is updated.
  ///
  /// @param newMaxGasPrice The new maximum gas price.
  event SetMaxGasPrice(uint256 newMaxGasPrice);

  /// @notice The address of the whitelisted gelato contract.
  address public gelatoPoker;
  /// @notice The maximum gas price to be spent on any call from the gelato poker.
  uint256 public maxGasPrice;

  constructor(address _gelatoPoker, uint256 _maxGasPrice) Ownable() {
    gelatoPoker = _gelatoPoker;
    maxGasPrice = _maxGasPrice;
  }

  /// @notice Sets the address of the whitelisted gelato poker contract.
  ///
  /// @param newPoker The new address of the gelato poker.
  function setPoker(address newPoker) external onlyOwner {
    gelatoPoker = newPoker;
    emit SetPoker(gelatoPoker);
  }

  /// @notice Sets the maximum gas price that can be used for an upkeep call.
  ///
  /// @param newGasPrice The new maximum gas price.
  function setMaxGasPrice(uint256 newGasPrice) external onlyOwner {
    maxGasPrice = newGasPrice;
    emit SetMaxGasPrice(maxGasPrice);
  }
}
