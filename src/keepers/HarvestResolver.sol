pragma solidity ^0.8.13;

import "../interfaces/keepers/IResolver.sol";
import "../interfaces/IAlchemistV2.sol";
import "../interfaces/keepers/IAlchemixHarvester.sol";
import "../interfaces/ITokenAdapter.sol";
import "../interfaces/external/vesper/IVesperRewards.sol";
import "../utils/UniswapEstimatedPrice.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "../libraries/SafeCast.sol";
import "../base/Errors.sol";

contract HarvestResolver is IResolver, Ownable {
  address constant ethAlchemistAddress = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
  address constant usdAlchemistAddress = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
  address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address constant uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  address constant wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address constant vaDAI = 0x0538C8bAc84E95A9dF8aC10Aad17DbE81b9E36ee;
  address constant vaUSDC = 0xa8b607Aa09B6A2E306F93e74c282Fb13f6A80452;
  address constant vaETH = 0xd1C117319B3595fbc39b471AB1fd485629eb05F2;

  /// @notice Thrown when the yield token of a harvest job being added is disabled in the alchemist of the harvest job being added.
  error YieldTokenDisabled();
  /// @notice Thrown when attempting to remove a harvest job that does not currently exist.
  error HarvestJobDoesNotExist();

  /// @notice Emitted when details of a harvest job are set.
  event SetHarvestJob(
    bool active,
    address alchemist,
    address rewardToken,
    address yieldToken,
    uint256 minimumHarvestAmount,
    uint256 minimumDelay,
    uint256 slippageBps
  );
  /// @notice Emitted when a harvester status is updated.
  event SetHarvester(address harvester, bool status);

  /// @notice Emitted when a harvest job is removed from the list.
  event RemoveHarvestJob(address yieldToken);

  /// @notice Emitted when a harvest is recorded.
  event RecordHarvest(address yieldToken);

  struct HarvestJob {
    bool active;
    address yieldToken;
    address alchemist;
    address rewardToken;
    uint256 lastHarvest;
    uint256 minimumHarvestAmount;
    uint256 minimumDelay;
    uint256 slippageBps;
  }

  uint256 public constant SLIPPAGE_PRECISION = 10000;

  /// @dev The list of yield tokens that define harvest jobs.
  address[] public yieldTokens;

  /// @dev yieldToken => HarvestJob.
  mapping(address => HarvestJob) public harvestJobs;

  /// @dev Whether or not the resolver is paused.
  bool public paused;

  /// @dev A mapping of the registered harvesters.
  mapping(address => bool) public harvesters;

  constructor() Ownable() {}

  modifier onlyHarvester() {
    if (!harvesters[msg.sender]) {
      revert Unauthorized();
    }
    _;
  }

  /// @notice Enables or disables a harvester from calling protected harvester-only functions.
  ///
  /// @param harvester The address of the target harvester.
  /// @param status The status to set for the target harvester.
  function setHarvester(address harvester, bool status) external onlyOwner {
    harvesters[harvester] = status;
    emit SetHarvester(harvester, status);
  }

  /// @notice Pauses and un-pauses the resolver.
  ///
  /// @param pauseState The pause state to set.
  function setPause(bool pauseState) external onlyOwner {
    paused = pauseState;
  }

  /// @notice Remove tokens that were accidentally sent to the resolver.
  ///
  /// @param token The token to remove.
  function recoverFunds(address token) external onlyOwner {
    IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
  }

  /// @notice Sets the parameters of a harvest job and adds it to the list if needed.
  ///
  /// @param active               A flag for whether or not the harvest job is active.
  /// @param yieldToken           The address of the yield token to be harvested.
  /// @param alchemist            The address of the alchemist to be harvested.
  /// @param rewardToken          Address of the reward token. 0 for none.
  /// @param minimumHarvestAmount The minimum amount of harvestable funds required in order to run the harvest job.
  /// @param minimumDelay         The minimum delay (in seconds) needed between successive runs of the job.
  function addHarvestJob(
    bool active,
    address yieldToken,
    address alchemist,
    address rewardToken,
    uint256 minimumHarvestAmount,
    uint256 minimumDelay,
    uint256 slippageBps
  ) external onlyOwner {
    IAlchemistV2.YieldTokenParams memory ytp = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken);
    if (!ytp.enabled) {
      revert YieldTokenDisabled();
    }

    if (slippageBps > SLIPPAGE_PRECISION) {
      revert IllegalArgument();
    }

    harvestJobs[yieldToken] = HarvestJob(
      active,
      yieldToken,
      alchemist,
      rewardToken,
      block.timestamp,
      minimumHarvestAmount,
      minimumDelay,
      slippageBps
    );

    emit SetHarvestJob(active, alchemist, rewardToken, yieldToken, minimumHarvestAmount, minimumDelay, slippageBps);

    // Only add the yield token to the list if it doesnt exist yet.
    for (uint256 i = 0; i < yieldTokens.length; i++) {
      if (yieldTokens[i] == yieldToken) {
        return;
      }
    }
    yieldTokens.push(yieldToken);
  }

  /// @notice Sets if a harvest job is active.
  ///
  /// @param yieldToken   The address of the yield token to be harvested.
  /// @param active       A flag for whether or not the harvest job is active.
  function setActive(address yieldToken, bool active) external onlyOwner {
    harvestJobs[yieldToken].active = active;
  }

  /// @notice Sets the alchemist of a harvest job.
  ///
  /// @param yieldToken   The address of the yield token to be harvested.
  /// @param alchemist    The address of the alchemist to be harvested.
  function setAlchemist(address yieldToken, address alchemist) external onlyOwner {
    IAlchemistV2.YieldTokenParams memory ytp = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken);
    if (!ytp.enabled) {
      revert YieldTokenDisabled();
    }
    harvestJobs[yieldToken].alchemist = alchemist;
  }

  /// @notice Sets the minimum harvest amount of a harvest job.
  ///
  /// @param yieldToken           The address of the yield token to be harvested.
  /// @param minimumHarvestAmount The minimum amount of harvestable funds required in order to run the harvest job.
  function setMinimumHarvestAmount(address yieldToken, uint256 minimumHarvestAmount) external onlyOwner {
    harvestJobs[yieldToken].minimumHarvestAmount = minimumHarvestAmount;
  }

  /// @notice Sets the minimum delay of a harvest job.
  ///
  /// @param yieldToken   The address of the yield token to be harvested.
  /// @param minimumDelay The minimum delay (in seconds) needed between successive runs of the job.
  function setMinimumDelay(address yieldToken, uint256 minimumDelay) external onlyOwner {
    harvestJobs[yieldToken].minimumDelay = minimumDelay;
  }

  /// @notice Sets the amount of slippage for a harvest job.
  ///
  /// @param yieldToken   The address of the yield token to be harvested.
  /// @param slippageBps  The amount of slippage to accept during a harvest.
  function setSlippageBps(address yieldToken, uint256 slippageBps) external onlyOwner {
    harvestJobs[yieldToken].slippageBps = slippageBps;
  }

  /// @notice Removes a harvest job from the list of harvest jobs.
  ///
  /// @param yieldToken The address of the yield token to remove.
  function removeHarvestJob(address yieldToken) external onlyOwner {
    int256 idx = -1;
    for (uint256 i = 0; i < yieldTokens.length; i++) {
      if (yieldTokens[i] == yieldToken) {
        idx = SafeCast.toInt256(i);
      }
    }
    if (idx > -1) {
      delete harvestJobs[yieldToken];
      yieldTokens[SafeCast.toUint256(idx)] = yieldTokens[yieldTokens.length - 1];
      yieldTokens.pop();
      emit RemoveHarvestJob(yieldToken);
    } else {
      revert HarvestJobDoesNotExist();
    }
  }

  /// @notice Check if there is a harvest that needs to be run.
  ///
  /// Returns FALSE if the resolver is paused.
  /// Returns TRUE for the first harvest job that meets the following criteria:
  ///     - the harvest job is active
  ///     - `yieldToken` is enabled in the Alchemist
  ///     - minimumDelay seconds have passed since the `yieldToken` was last harvested
  ///     - the expected harvest amount is greater than minimumHarvestAmount
  /// Returns FALSE if no harvest jobs meet the above criteria.
  ///
  /// @return canExec     If a harvest is needed
  /// @return execPayload The payload to forward to the AlchemixHarvester
  function checker() external view returns (bool canExec, bytes memory execPayload) {
    if (paused) {
      return (false, abi.encode(0));
    }

    for (uint256 i = 0; i < yieldTokens.length; i++) {
      address yieldToken = yieldTokens[i];
      HarvestJob memory h = harvestJobs[yieldToken];
      if (h.active) {
        IAlchemistV2.YieldTokenParams memory ytp = IAlchemistV2(h.alchemist).getYieldTokenParameters(yieldToken);

        if (ytp.enabled) {
          uint256 pps = ITokenAdapter(ytp.adapter).price();
          uint256 currentValue = ((ytp.activeBalance + ytp.harvestableBalance) * pps) / 10**ytp.decimals;
          if (
            (block.timestamp >= h.lastHarvest + h.minimumDelay) &&
            (currentValue > ytp.expectedValue + h.minimumHarvestAmount)
          ) {
            uint256 minimumAmountOut = currentValue - ytp.expectedValue;
            minimumAmountOut = minimumAmountOut - (minimumAmountOut * h.slippageBps) / SLIPPAGE_PRECISION;

            // If vault has rewards ot be collected
            if (h.rewardToken != address(0)) {
              uint256 expectedExchange;
              // alUSD route
              if (h.alchemist == usdAlchemistAddress) {
                if (h.yieldToken == vaDAI) {
                  (address[] memory tokens, uint256[] memory amounts) = IVesperRewards(0x35864296944119F72AA1B468e13449222f3f0E67).claimable(usdAlchemistAddress);
                  expectedExchange = _getExpectedExchange(uniswapFactory, h.rewardToken, wethAddress, uint24(3000), dai, uint24(3000), amounts[0]);
                } else if (h.yieldToken == vaUSDC) {
                  (address[] memory tokens, uint256[] memory amounts) = IVesperRewards(0x2F59B0F98A08E733C66dFB42Bd8E366dC2cfedA6).claimable(usdAlchemistAddress);
                  expectedExchange = _getExpectedExchange(uniswapFactory, h.rewardToken, wethAddress, uint24(3000), dai, uint24(3000), amounts[0]);
                }
              // alETH route
              } else if (h.alchemist == ethAlchemistAddress) {
                (address[] memory tokens, uint256[] memory amounts) = IVesperRewards(0x51EEf73abf5d4AC5F41De131591ed82c27a7Be3D).claimable(ethAlchemistAddress);
                expectedExchange = _getExpectedExchange(uniswapFactory, h.rewardToken, wethAddress, uint24(3000), address(0), uint24(0), amounts[0]);
              }
              return (
                true,
                abi.encodeWithSelector(IAlchemixHarvester.harvest.selector, h.alchemist, yieldToken, minimumAmountOut, expectedExchange * 9900 / 10000)
              );
            } else {
              return (
                true,
                abi.encodeWithSelector(IAlchemixHarvester.harvest.selector, h.alchemist, yieldToken, minimumAmountOut, 0)
              );
            }
          }
        }
      }
    }
    return (false, abi.encode(0));
  }

  // Get expected exchange from reward token to debt token.
  function _getExpectedExchange(address factory, address token0, address token1, uint24 fee0, address token2, uint24 fee1, uint256 amount) internal view returns (uint256) {
      IUniswapV3Factory uniswapFactory = IUniswapV3Factory(factory);

      IUniswapV3Pool pool = IUniswapV3Pool(uniswapFactory.getPool(token0, token1, fee0));
      (uint160 sqrtPriceX96,,,,,,) =  pool.slot0();
      uint256 price0 = uint(sqrtPriceX96) * (uint(sqrtPriceX96)) * (1e18) >> (96 * 2);

      if (token2 == address(0)) return amount * price0 / 1e18;

      pool = IUniswapV3Pool(uniswapFactory.getPool(token1, token2, fee1));
      ( sqrtPriceX96,,,,,,) =  pool.slot0();
      uint256 price1 = uint(sqrtPriceX96) * (uint(sqrtPriceX96)) * (1e18) >> (96 * 2);

      return amount * price0 / price1;
  }

  function recordHarvest(address yieldToken) external onlyHarvester {
    harvestJobs[yieldToken].lastHarvest = block.timestamp;
    emit RecordHarvest(yieldToken);
  }
}
