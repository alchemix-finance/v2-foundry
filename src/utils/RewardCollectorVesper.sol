pragma solidity ^0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {ISwapRouter} from "../interfaces/external/uniswap/ISwapRouter.sol";
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

/// @title  RewardCollectorVesper
/// @author Alchemix Finance
contract RewardCollectorVesper is IRewardCollector {
    uint256 constant FIXED_POINT_SCALAR = 1e18;
    uint256 constant BPS = 10000;
    string public override version = "1.0.0";
    address public alchemist;
    address public debtToken;
    address public override rewardToken;
    address public override swapRouter;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        debtToken       = params.debtToken;
        rewardToken     = params.rewardToken;
        swapRouter      = params.swapRouter;
    }

    function claimAndDistributeRewards(address[] calldata tokens, uint256 minimumSwap) external returns (uint256) {
        uint256 totalClaimed;

        IAlchemistV2(alchemist).sweepRewardTokens(rewardToken);
        for (uint i = 0; i < tokens.length; i++) {
            uint256 claimed = IERC20(rewardToken).balanceOf(address(this));
            uint256 received;

            if (claimed == 0) continue;

            totalClaimed += claimed;

            if (debtToken == 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9) {
                bytes memory swapPath = abi.encodePacked(rewardToken, uint24(3000), WETH);

                TokenUtils.safeApprove(rewardToken, swapRouter, claimed);
                ISwapRouter.ExactInputParams memory params =
                    ISwapRouter.ExactInputParams({
                        path: swapPath,
                        recipient: address(this),
                        amountIn: claimed,
                        amountOutMinimum: minimumSwap
                    });

                received = ISwapRouter(swapRouter).exactInput(params);
            
            } else if (debtToken == 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6) {
                bytes memory swapPath = abi.encodePacked(rewardToken, uint24(3000), WETH);

                TokenUtils.safeApprove(rewardToken, swapRouter, claimed);
                ISwapRouter.ExactInputParams memory params =
                    ISwapRouter.ExactInputParams({
                        path: swapPath,
                        recipient: address(this),
                        amountIn: claimed,
                        amountOutMinimum: minimumSwap
                    });

                received = ISwapRouter(swapRouter).exactInput(params);

            } else {
                revert IllegalState("Reward collector `debtToken` is not supported");
            }

            // Donate to alchemist depositors
            IAlchemistV2(alchemist).donate(tokens[i], IERC20(debtToken).balanceOf(address(this)));
        }
        return totalClaimed;
    }
}