pragma solidity ^0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IStaticAToken} from "../interfaces/external/aave/IStaticAToken.sol";
import {IVelodromeSwapRouter} from "../interfaces/external/velodrome/IVelodromeSwapRouter.sol";
import {Unauthorized, IllegalState, IllegalArgument} from "../base/ErrorMessages.sol";

import "../interfaces/IRewardCollector.sol";
import "../libraries/Sets.sol";
import "../libraries/TokenUtils.sol";

struct InitializationParams {
    address alchemist;
    address debtToken;
    address rewardToken;
    address swapRouter;
}

/// @title  RewardCollectorOptimism
/// @author Alchemix Finance
contract RewardCollectorOptimism is IRewardCollector {
    uint256 constant FIXED_POINT_SCALAR = 1e18;
    uint256 constant BPS = 10000;
    string public override version = "1.0.0";
    address public alchemist;
    address public debtToken;
    address public override rewardToken;
    address public override swapRouter;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        debtToken       = params.debtToken;
        rewardToken     = params.rewardToken;
        swapRouter      = params.swapRouter;
    }

    function claimAndDistributeRewards(address token, uint256 minimumAmountOut) external returns (uint256) {
        IStaticAToken(token).claimRewards();
        uint256 claimed = IERC20(rewardToken).balanceOf(address(this));

        if (claimed == 0) return 0;

        if (debtToken == 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A) {
            // Velodrome Swap Routes: OP -> USDC -> alUSD
            IVelodromeSwapRouter.route[] memory routes = new IVelodromeSwapRouter.route[](2);
            routes[0] = IVelodromeSwapRouter.route(0x4200000000000000000000000000000000000042, 0x7F5c764cBc14f9669B88837ca1490cCa17c31607, false);
            routes[1] = IVelodromeSwapRouter.route(0x7F5c764cBc14f9669B88837ca1490cCa17c31607, 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A, true);
            TokenUtils.safeApprove(rewardToken, swapRouter, claimed);
            IVelodromeSwapRouter(swapRouter).swapExactTokensForTokens(claimed, minimumAmountOut, routes, address(this), block.timestamp);
        } else if (debtToken == 0x3E29D3A9316dAB217754d13b28646B76607c5f04) {
            // Velodrome Swap Routes: OP -> WETH -> alETH
            IVelodromeSwapRouter.route[] memory routes = new IVelodromeSwapRouter.route[](1);
            routes[0] = IVelodromeSwapRouter.route(0x4200000000000000000000000000000000000042, 0x4200000000000000000000000000000000000006, false);
            routes[1] = IVelodromeSwapRouter.route(0x4200000000000000000000000000000000000006, 0x3E29D3A9316dAB217754d13b28646B76607c5f04, false);
            TokenUtils.safeApprove(rewardToken, swapRouter, claimed);
            IVelodromeSwapRouter(swapRouter).swapExactTokensForTokens(claimed, minimumAmountOut, routes, address(this), block.timestamp);
        } else {
            revert IllegalState("Reward collector `debtToken` is not supported");
        }

        // Donate to alchemist depositors
        uint256 debtReturned = IERC20(debtToken).balanceOf(address(this));
        TokenUtils.safeApprove(debtToken, alchemist, debtReturned);
        IAlchemistV2(alchemist).donate(token, debtReturned);

        return claimed;
    }
}