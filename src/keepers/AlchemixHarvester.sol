pragma solidity ^0.8.13;

import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./AlchemixGelatoKeeper.sol";
import "../interfaces/IAlchemistV2.sol";
import "../interfaces/keepers/IHarvestResolver.sol";
import "../interfaces/keepers/IAlchemixHarvester.sol";
import "../interfaces/IRewardRouter.sol";
import "../interfaces/ITokenAdapter.sol";
import "../keepers/HarvestResolver.sol";

contract AlchemixHarvester is IAlchemixHarvester, AlchemixGelatoKeeper {

  uint256 public constant SLIPPAGE_PRECISION = 10000;

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
  function harvest(
    address alchemist,
    address yieldToken
  ) external override {
    if (msg.sender != gelatoPoker) {
      revert Unauthorized();
    }
    
    if (tx.gasprice > maxGasPrice) {
      revert TheGasIsTooDamnHigh();
    }

    HarvestResolver.HarvestJob memory h = IHarvestResolver(resolver).harvestJobs(yieldToken);

    IAlchemistV2.YieldTokenParams memory ytp = IAlchemistV2(h.alchemist).getYieldTokenParameters(yieldToken);
    
    uint256 pps = ITokenAdapter(ytp.adapter).price();
    uint256 currentValue = ((ytp.activeBalance + ytp.harvestableBalance) * pps) / 10**ytp.decimals;

    uint256 minimumAmountOut = currentValue - ytp.expectedValue;
    minimumAmountOut = minimumAmountOut - (minimumAmountOut * h.slippageBps) / SLIPPAGE_PRECISION;

    IAlchemistV2(alchemist).harvest(yieldToken, minimumAmountOut);

    (address rewardCollector, , , ,) = IRewardRouter(rewardRouter).getRewardCollector(yieldToken);

    if (rewardCollector != address(0)) {
      IRewardRouter(rewardRouter).distributeRewards(yieldToken);
    }

    IHarvestResolver(resolver).recordHarvest(yieldToken);
  }
}
