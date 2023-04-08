pragma solidity ^0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../../interfaces/IAlchemistV2.sol";
import {IStakingRewards} from "../../interfaces/external/yearn/IStakingRewards.sol";
import {IYearnStakingToken} from "../../interfaces/external/yearn/IYearnStakingToken.sol";
import {IVelodromeSwapRouter} from "../../interfaces/external/velodrome/IVelodromeSwapRouter.sol";
import {Unauthorized, IllegalState, IllegalArgument} from "../../base/ErrorMessages.sol";

import "../../interfaces/external/aave/IRewardsController.sol";
import "../../interfaces/external/chainlink/IChainlinkOracle.sol";

import "../../interfaces/IRewardCollector.sol";
import "../../libraries/Sets.sol";
import "../../libraries/TokenUtils.sol";

struct InitializationParams {
    address alchemist;
    address debtToken;
    address rewardToken;
    address swapRouter;
}

/// @title  OptimismYearnRewardCollector
/// @author Alchemix Finance
contract OptimismYearnRewardCollector is IRewardCollector {
    address constant alUsdOptimism = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address constant alEthOptimism = 0x3E29D3A9316dAB217754d13b28646B76607c5f04;
    address constant opToUsdOracle = 0x0D276FC14719f9292D5C1eA2198673d1f4269246;
    address constant ethToUsdOracle = 0x13e3Ee699D1909E989722E753853AE30b17e08c5;

    uint256 constant FIXED_POINT_SCALAR = 1e18;
    uint256 constant BPS = 10000;
    string public override version = "1.0.0";
    address public alchemist;
    address public debtToken;
    address public override rewardToken;
    address public override swapRouter;

    /// @notice Emitted when a donation occurs.
    ///
    /// @param token The yield token that received a donation.
    /// @param amount The amount of debt tokens donated.
    event RewardsDonated(address token, uint256 amount);


    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        debtToken       = params.debtToken;
        rewardToken     = params.rewardToken;
        swapRouter      = params.swapRouter;
    }

    function claimAndDonateRewards(address token, uint256 minimumAmountOut) external {
        IYearnStakingToken(token).claimRewards();

        // Amount of reward token claimed plus any sent to this contract from grants.
        uint256 amountRewardToken = IERC20(rewardToken).balanceOf(address(this));

        if (amountRewardToken == 0) return;

        if (debtToken == 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A) {
            // Velodrome Swap Routes: OP -> USDC -> alUSD
            IVelodromeSwapRouter.route[] memory routes = new IVelodromeSwapRouter.route[](2);
            routes[0] = IVelodromeSwapRouter.route(0x4200000000000000000000000000000000000042, 0x7F5c764cBc14f9669B88837ca1490cCa17c31607, false);
            routes[1] = IVelodromeSwapRouter.route(0x7F5c764cBc14f9669B88837ca1490cCa17c31607, 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A, true);
            TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardToken);
            IVelodromeSwapRouter(swapRouter).swapExactTokensForTokens(amountRewardToken, minimumAmountOut, routes, address(this), block.timestamp);
        } else if (debtToken == 0x3E29D3A9316dAB217754d13b28646B76607c5f04) {
            // Velodrome Swap Routes: OP -> alETH
            IVelodromeSwapRouter.route[] memory routes = new IVelodromeSwapRouter.route[](1);
            routes[0] = IVelodromeSwapRouter.route(0x4200000000000000000000000000000000000042, 0x3E29D3A9316dAB217754d13b28646B76607c5f04, false);
            TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardToken);
            IVelodromeSwapRouter(swapRouter).swapExactTokensForTokens(amountRewardToken, minimumAmountOut, routes, address(this), block.timestamp);
        } else {
            revert IllegalState("Reward collector `debtToken` is not supported");
        }

        // Donate to alchemist depositors
        uint256 debtReturned = IERC20(debtToken).balanceOf(address(this));
        TokenUtils.safeApprove(debtToken, alchemist, debtReturned);
        IAlchemistV2(alchemist).donate(token, debtReturned);

        emit RewardsDonated(token, debtReturned);
    }

    function getExpectedExchange(address yieldToken) external view returns (uint256) {
        uint256 expectedExchange;
        uint256 claimable = IStakingRewards(IYearnStakingToken(yieldToken).STAKNG_REWARDS()).earned(yieldToken);
        uint256 totalToSwap = claimable + TokenUtils.safeBalanceOf(rewardToken, address(this));

        // Ensure that round is complete, otherwise price is stale.
        // OP to USD
        (
            uint80 roundID,
            int256 opToUsd,
            ,
            uint256 updateTime,
            uint80 answeredInRound
        ) = IChainlinkOracle(opToUsdOracle).latestRoundData();
        require(
            answeredInRound >= roundID,
            "Chainlink Price Stale"
        );

        require(opToUsd > 0, "Chainlink Malfunction");
        require(updateTime != 0, "Incomplete round");

        // OP to ETH
        (
            uint80 roundID2,
            int256 ethToUsd,
            ,
            uint256 updateTime2,
            uint80 answeredInRound2
        ) = IChainlinkOracle(ethToUsdOracle).latestRoundData();
        require(
            answeredInRound2 >= roundID2,
            "Chainlink Price Stale"
        );

        require(ethToUsd > 0, "Chainlink Malfunction");
        require(updateTime2 != 0, "Incomplete round");

        if (debtToken == alUsdOptimism) {
            expectedExchange = totalToSwap * uint256(opToUsd) / 1e8;
        } else if (debtToken == alEthOptimism) {
            expectedExchange = totalToSwap * uint256(opToUsd) / uint256(ethToUsd);
        } else {
            revert IllegalState("Invalid debt token");
        }

        return expectedExchange;
    }
}