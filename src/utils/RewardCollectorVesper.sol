pragma solidity ^0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2State} from "../interfaces/alchemist/IAlchemistV2State.sol";
import {ICurveFactoryethpool} from "../interfaces/ICurveFactoryethpool.sol";
import {IStableMetaPool} from "../interfaces/external/curve/IStableMetaPool.sol";
import {ISwapRouter} from "../interfaces/external/uniswap/ISwapRouter.sol";
import {IVesperPool} from "../interfaces/external/vesper/IVesperPool.sol";
import {IVesperRewards} from "../interfaces/external/vesper/IVesperRewards.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";


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
    address constant alUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address constant alETH = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant curveFactoryPool = 0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e;
    address constant curveMetaPool = 0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        debtToken       = params.debtToken;
        rewardToken     = params.rewardToken;
        swapRouter      = params.swapRouter;
    }

    function claim(address yieldToken) external {
        IVesperRewards(IVesperPool(yieldToken).poolRewards()).claimReward(address(this));
    }

    function claimAndDistributeRewards(address token, uint256 minimumAmountOut) external returns (uint256) {

        if (
            IAlchemistV2(alchemist).isSupportedYieldToken(rewardToken) || 
            IAlchemistV2(alchemist).isSupportedUnderlyingToken(rewardToken)
        ) {
            revert IllegalArgument("Invalid reward token");
        }

        IAlchemistV2(alchemist).sweepRewardTokens(rewardToken, token);

        uint256 claimed = IERC20(rewardToken).balanceOf(address(this));
        uint256 received;
        
        if (claimed == 0) return 0;

        if (debtToken == alUSD) {
            // Swap VSP -> WETH -> DAI
            // As of now this will only swap DAI for alUSD in curve
            // Possibly need to rotate which tokens get used
            bytes memory swapPath = abi.encodePacked(rewardToken, uint24(3000), WETH, uint24(3000), DAI);

            ISwapRouter.ExactInputParams memory params =
                ISwapRouter.ExactInputParams({
                    path: swapPath,
                    recipient: address(this),
                    amountIn: claimed,
                    amountOutMinimum: minimumAmountOut
                });

            received = ISwapRouter(swapRouter).exactInput(params);
            // Curve 3CRV + alUSD meta pool swap to alUSD
            IStableMetaPool(curveMetaPool).exchange_underlying(1, 0, received, received * 9900 / BPS);
        } else if (debtToken == alETH) {
            // Swap VSP -> WETH
            bytes memory swapPath = abi.encodePacked(rewardToken, uint24(3000), WETH);

            ISwapRouter.ExactInputParams memory params =
                ISwapRouter.ExactInputParams({
                    path: swapPath,
                    recipient: address(this),
                    amountIn: claimed,
                    amountOutMinimum: minimumAmountOut
                });

            received = ISwapRouter(swapRouter).exactInput(params);
            IWETH9(WETH).withdraw(received);
            // Curve alETH + ETH factory pool swap to alETH
            ICurveFactoryethpool(curveFactoryPool).exchange{value: received}(0, 1, received, received * 9900 / BPS);
        } else {
            revert IllegalState("Reward collector `debtToken` is not supported");
        }

        IAlchemistV2(alchemist).donate(token, IERC20(debtToken).balanceOf(address(this)));

        return claimed;
    }

    receive() external payable {}
}