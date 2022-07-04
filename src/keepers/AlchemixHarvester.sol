pragma solidity ^0.8.11;

import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./AlchemixGelatoKeeper.sol";
import "../interfaces/IAlchemistV2.sol";
import "../interfaces/keepers/IHarvestResolver.sol";
import "../interfaces/keepers/IAlchemixHarvester.sol";

contract AlchemixHarvester is IAlchemixHarvester, AlchemixGelatoKeeper {
  /// @notice The address of the resolver.
  address public resolver;

  constructor(
    address _gelatoPoker,
    uint256 _maxGasPrice,
    address _resolver
  ) AlchemixGelatoKeeper(_gelatoPoker, _maxGasPrice) {
    resolver = _resolver;
  }

  function setResolver(address _resolver) external onlyOwner {
    resolver = _resolver;
  }

  /// @notice Runs a the specified harvest job.
  ///
  /// @param alchemist        The address of the target alchemist.
  /// @param yieldToken       The address of the target yield token.
  /// @param minimumAmountOut The minimum amount of tokens expected to be harvested.
  function harvest(
    address alchemist,
    address yieldToken,
    uint256 minimumAmountOut
  ) external override {
    if (msg.sender != gelatoPoker) {
      revert Unauthorized();
    }
    if (tx.gasprice > maxGasPrice) {
      revert TheGasIsTooDamnHigh();
    }
    IAlchemistV2(alchemist).harvest(yieldToken, minimumAmountOut);
    IHarvestResolver(resolver).recordHarvest(yieldToken);
  }
}
