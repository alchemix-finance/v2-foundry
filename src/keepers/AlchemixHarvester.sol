pragma solidity ^0.8.13;

import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./AlchemixGelatoKeeper.sol";
import "../interfaces/IAlchemistV2.sol";
import "../interfaces/keepers/IHarvestResolver.sol";
import "../interfaces/keepers/IAlchemixHarvester.sol";
import "../interfaces/IRewardRouter.sol";

contract AlchemixHarvester is IAlchemixHarvester, AlchemixGelatoKeeper {
  /// @notice The address of the resolver.
  address public resolver;

  /// @notice The address of the Reward Router.
  address public rewardRouter;

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

  function setRewardRouter(address _rewardRouter) external onlyOwner {
    rewardRouter = _rewardRouter;
  }

  /// @notice Runs a the specified harvest job and donates optimism rewards.
  ///
  /// @param alchemist                The address of the target alchemist.
  /// @param yieldToken               The address of the target yield token.
  /// @param minimumAmountOut         The minimum amount of tokens expected to be harvested.
  /// @param expectedRewardsExchange  The minimum VSP to debt tokens.
  function harvest(
    address alchemist,
    address yieldToken,
    uint256 minimumAmountOut,
    uint256 expectedRewardsExchange
  ) external override {
    if (msg.sender != gelatoPoker) {
      revert Unauthorized();
    }
    if (tx.gasprice > maxGasPrice) {
      revert TheGasIsTooDamnHigh();
    }
    IAlchemistV2(alchemist).harvest(yieldToken, minimumAmountOut);

    (address rewardCollector, , ) = IRewardRouter(rewardRouter).getRewardCollector(yieldToken);

    if (rewardCollector != address(0)) {
      IRewardRouter(rewardRouter).claimAndDistributeRewards(yieldToken, expectedRewardsExchange);
    }

    IHarvestResolver(resolver).recordHarvest(yieldToken);
  }
}
