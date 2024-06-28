pragma solidity ^0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../../interfaces/IAlchemistV2.sol";
import {IVelodromeSwapRouter} from "../../interfaces/external/velodrome/IVelodromeSwapRouter.sol";
import {IVeloOracle} from "../../interfaces/external/velodrome/IVeloOracle.sol";
import {Unauthorized, IllegalState, IllegalArgument} from "../../base/ErrorMessages.sol";

import "../../interfaces/external/chainlink/IChainlinkOracle.sol";


import "../../interfaces/IRewardCollector.sol";
import "../../libraries/Sets.sol";
import "../../libraries/TokenUtils.sol";
import "../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";


struct InitializationParams {
    address alchemist;
    address debtToken;
    address rewardRouter;
    address rewardToken;
    address swapRouter;
}

/// @title  RewardCollectorOptimism
/// @author Alchemix Finance
contract OptimismRewardCollector is IRewardCollector, Ownable {
    address constant aaveIncentives = 0x929EC64c34a17401F460460D4B9390518E5B473e;
    address constant alUsdOptimism = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address constant alEthOptimism = 0x3E29D3A9316dAB217754d13b28646B76607c5f04;
    address constant opToUsdOracle = 0x0D276FC14719f9292D5C1eA2198673d1f4269246;
    address constant ethToUsdOracle = 0x13e3Ee699D1909E989722E753853AE30b17e08c5;
    uint256 constant FIXED_POINT_SCALAR = 1e18;
    uint256 constant BPS = 10000;
    string public override version = "1.1.0";
    address public alchemist;
    address public debtToken;
    address public rewardRouter;
    address public override rewardToken;
    address public override swapRouter;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        debtToken       = params.debtToken;
        rewardToken     = params.rewardToken;
        rewardRouter    = params.rewardRouter;
        swapRouter      = params.swapRouter;
    }

    function setRewardRouter(address _rewardRouter) external onlyOwner {
        rewardRouter = _rewardRouter;
    }

    function claimAndDonateRewards(address token, uint256 minimumAmountOut) external returns (uint256) {
        require(msg.sender == rewardRouter, "Must be Reward Router"); 

        // Amount of reward token claimed plus any sent to this contract from grants.
        uint256 amountRewardToken = IERC20(rewardToken).balanceOf(address(this));

        if (amountRewardToken == 0) return 0;

        if (debtToken == 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A) {
            // Velodrome Swap Routes: OP -> USDC -> alUSD
            IVelodromeSwapRouter.Route[] memory routes = new IVelodromeSwapRouter.Route[](2);
            routes[0] = IVelodromeSwapRouter.Route(0x4200000000000000000000000000000000000042, 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85, false, 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a);
            routes[1] = IVelodromeSwapRouter.Route(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85, 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A, true, 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a);
            TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardToken);
            IVelodromeSwapRouter(swapRouter).swapExactTokensForTokens(amountRewardToken, minimumAmountOut, routes, address(this), block.timestamp);
        } else if (debtToken == 0x3E29D3A9316dAB217754d13b28646B76607c5f04) {
            // Velodrome Swap Routes: OP -> alETH
            IVelodromeSwapRouter.Route[] memory routes = new IVelodromeSwapRouter.Route[](2);
            routes[0] = IVelodromeSwapRouter.Route(0x4200000000000000000000000000000000000042, 0x4200000000000000000000000000000000000006, false, 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a);
            routes[1] = IVelodromeSwapRouter.Route(0x4200000000000000000000000000000000000006, 0x3E29D3A9316dAB217754d13b28646B76607c5f04, true, 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a);
            TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardToken);
            IVelodromeSwapRouter(swapRouter).swapExactTokensForTokens(amountRewardToken, minimumAmountOut, routes, address(this), block.timestamp);
        } else {
            revert IllegalState("Reward collector `debtToken` is not supported");
        }

        // Donate to alchemist depositors
        uint256 debtReturned = IERC20(debtToken).balanceOf(address(this));
        TokenUtils.safeApprove(debtToken, alchemist, debtReturned);
        IAlchemistV2(alchemist).donate(token, debtReturned);

        return amountRewardToken;
    }

    function getExpectedExchange() external view returns (uint256) {
        uint256 expectedExchange;
        uint256 totalToSwap = TokenUtils.safeBalanceOf(rewardToken, address(this));

        // Find expected amount out before calling harvest
        if (debtToken == alUsdOptimism) {
            IERC20[] memory connectors = new IERC20[](3);
            connectors[0] = IERC20(0x4200000000000000000000000000000000000042);
            connectors[1] = IERC20(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85);
            connectors[2] = IERC20(0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A);
            uint256[] memory opToAlusd = IVeloOracle(0x395942C2049604a314d39F370Dfb8D87AAC89e16).getManyRatesWithConnectors(1, connectors);
            expectedExchange = totalToSwap * opToAlusd[0] / 1e18;
        } else if (debtToken == alEthOptimism) {
            IERC20[] memory connectors = new IERC20[](3);
            connectors[0] = IERC20(0x4200000000000000000000000000000000000042);
            connectors[1] = IERC20(0x4200000000000000000000000000000000000006);
            connectors[2] = IERC20(0x3E29D3A9316dAB217754d13b28646B76607c5f04);
            uint256[] memory opToAleth = IVeloOracle(0x395942C2049604a314d39F370Dfb8D87AAC89e16).getManyRatesWithConnectors(1, connectors);
            expectedExchange = totalToSwap * opToAleth[0] / 1e18;
        } else {
            revert IllegalState("Invalid debt token");
        }

        return expectedExchange;
    }
}