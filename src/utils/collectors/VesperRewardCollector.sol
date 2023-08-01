pragma solidity ^0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../../interfaces/IAlchemistV2.sol";
import {IAlchemistV2State} from "../../interfaces/alchemist/IAlchemistV2State.sol";
import {ICurveFactoryethpool} from "../../interfaces/ICurveFactoryethpool.sol";
import {IStableMetaPool} from "../../interfaces/external/curve/IStableMetaPool.sol";
import {ISwapRouter} from "../../interfaces/external/uniswap/ISwapRouter.sol";
import {IVesperPool} from "../../interfaces/external/vesper/IVesperPool.sol";
import {IVesperRewards} from "../../interfaces/external/vesper/IVesperRewards.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";


import {Unauthorized, IllegalState, IllegalArgument} from "../../base/ErrorMessages.sol";

import "../../utils/UniswapEstimatedPrice.sol";
import "../../interfaces/external/velodrome/IVelodromeSwapRouter.sol";
import "../../interfaces/IRewardCollector.sol";
import "../../libraries/Sets.sol";
import "../../libraries/TokenUtils.sol";

struct InitializationParams {
    address alchemist;
    address debtToken;
    address rewardToken;
    address swapRouter;
}

/// @title  RewardCollectorVesper
/// @author Alchemix Finance
contract VesperRewardCollector is IRewardCollector {
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
    address constant ethAlchemistAddress = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant usdAlchemistAddress = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant vaDAI = 0x0538C8bAc84E95A9dF8aC10Aad17DbE81b9E36ee;
    address constant vaUSDC = 0xa8b607Aa09B6A2E306F93e74c282Fb13f6A80452;
    address constant vaETH = 0xd1C117319B3595fbc39b471AB1fd485629eb05F2;
    address constant vesperRewardsDai = 0x35864296944119F72AA1B468e13449222f3f0E67;
    address constant vesperRewardsUsdc = 0x2F59B0F98A08E733C66dFB42Bd8E366dC2cfedA6;
    address constant vesperRewardsEth = 0x2F59B0F98A08E733C66dFB42Bd8E366dC2cfedA6;
    address constant vspRewardToken = 0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        debtToken       = params.debtToken;
        rewardToken     = params.rewardToken;
        swapRouter      = params.swapRouter;
    }

    function claim(address yieldToken) external {
        IVesperRewards(IVesperPool(yieldToken).poolRewards()).claimReward(address(this));
    }

    function claimAndDonateRewards(address token, uint256 minimumAmountOut) external returns (uint256) {
        IAlchemistV2(alchemist).sweepRewardTokens(rewardToken, token);

        // Tokens claimed from rewards plus any tokens sent to this contract from grants.
        uint256 amountRewardTokens = IERC20(rewardToken).balanceOf(address(this));
        uint256 received;
        
        if (amountRewardTokens == 0) return 0;

        if (debtToken == alUSD) {
            // Swap VSP -> WETH -> DAI
            // As of now this will only swap DAI for alUSD in curve
            // Possibly need to rotate which tokens get used
            bytes memory swapPath = abi.encodePacked(rewardToken, uint24(3000), WETH, uint24(3000), DAI);

            ISwapRouter.ExactInputParams memory params =
                ISwapRouter.ExactInputParams({
                    path: swapPath,
                    recipient: address(this),
                    amountIn: amountRewardTokens,
                    amountOutMinimum: minimumAmountOut
                });

            TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardTokens);
            received = ISwapRouter(swapRouter).exactInput(params);
            // Curve 3CRV + alUSD meta pool swap to alUSD
            TokenUtils.safeApprove(DAI, curveMetaPool, received);
            IStableMetaPool(curveMetaPool).exchange_underlying(1, 0, received, received * 9900 / BPS);
        } else if (debtToken == alETH) {
            // Swap VSP -> WETH
            bytes memory swapPath = abi.encodePacked(rewardToken, uint24(3000), WETH);

            ISwapRouter.ExactInputParams memory params =
                ISwapRouter.ExactInputParams({
                    path: swapPath,
                    recipient: address(this),
                    amountIn: amountRewardTokens,
                    amountOutMinimum: minimumAmountOut
                });

            TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardTokens);
            received = ISwapRouter(swapRouter).exactInput(params);
            IWETH9(WETH).withdraw(received);
            // Curve alETH + ETH factory pool swap to alETH
            ICurveFactoryethpool(curveFactoryPool).exchange{value: received}(0, 1, received, received * 9900 / BPS);
        } else {
            revert IllegalState("Reward collector `debtToken` is not supported");
        }

        uint256 debtReturned = IERC20(debtToken).balanceOf(address(this));
        TokenUtils.safeApprove(debtToken, alchemist, debtReturned);
        IAlchemistV2(alchemist).donate(token, debtReturned);

        return amountRewardTokens;
    }

    function getExpectedExchange(address yieldToken) external view returns (uint256) {
        uint256 expectedExchange;

        if (alchemist == usdAlchemistAddress) {
            if (yieldToken == vaDAI) {
                (address[] memory tokens, uint256[] memory amounts) = IVesperRewards(vesperRewardsDai).claimable(usdAlchemistAddress);
                expectedExchange = _getExpectedExchange(uniswapFactory, rewardToken, WETH, uint24(3000), DAI, uint24(3000), amounts[0] + TokenUtils.safeBalanceOf(rewardToken, address(this)));
            } else if (yieldToken == vaUSDC) {
                (address[] memory tokens, uint256[] memory amounts) = IVesperRewards(vesperRewardsUsdc).claimable(usdAlchemistAddress);
                expectedExchange = _getExpectedExchange(uniswapFactory, rewardToken, WETH, uint24(3000), DAI, uint24(3000), amounts[0] + TokenUtils.safeBalanceOf(rewardToken, address(this)));
            }
        } else if (alchemist == ethAlchemistAddress) {
            (address[] memory tokens, uint256[] memory amounts) = IVesperRewards(vesperRewardsEth).claimable(ethAlchemistAddress);
            expectedExchange = _getExpectedExchange(uniswapFactory, rewardToken, WETH, uint24(3000), address(0), uint24(0), amounts[0] + TokenUtils.safeBalanceOf(rewardToken, address(this)));
        }

        return expectedExchange;
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

    receive() external payable {}
}