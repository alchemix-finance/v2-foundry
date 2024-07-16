pragma solidity ^0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../../interfaces/IAlchemistV2.sol";
import {IERC4626} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
// TODO: Import the correct interface for Gearbox farming token
import {IFarmingPool} from "../../interfaces/external/gearbox/IFarmingPool.sol";
// TODO: Import the correct interface for Gearbox reward distributor
import {ISwapRouter} from "../../interfaces/external/uniswap/ISwapRouter.sol";
import {IChainlinkOracle} from "../../interfaces/external/chainlink/IChainlinkOracle.sol";

import {IRewardCollector} from "../../interfaces/IRewardCollector.sol";
import {Unauthorized, IllegalState, IllegalArgument} from "../../base/ErrorMessages.sol";

struct InitializationParams {
    address alchemist;
    address yieldToken;
    address alAsset;
    address rewardToken;
    address swapRouter;
}

/// @title GearboxRewardCollector
/// @author Alchemix Finance
contract GearboxRewardCollector is IRewardCollector {
    address constant gearboxRewardDistributor =0xf3b7994e4dA53E04155057Fd61dc501599d57877;
    //arb USDC rewards distributor address
    // address constant gearboxRewardDistributor = 0xD0181a36B0566a8645B7eECFf2148adE7Ecf2BE9;
    address constant alUsdOptimism = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address constant alEthArbitrum = 0x17573150d67d820542EFb24210371545a4868B03;
    address constant arbToUsdOracle = 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6;
    address constant ethToUsdOracle = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    uint256 constant FIXED_POINT_SCALAR = 1e18;
    uint256 constant BPS = 10000;
    string public override version = "1.0.0";
    address public alchemist;
    address public yieldToken;
    address public override rewardToken;
    address public override swapRouter;
    address public alAsset;

    constructor(InitializationParams memory params) {
        alchemist = params.alchemist;
        yieldToken = params.yieldToken;
        alAsset = params.alAsset;
        rewardToken = params.rewardToken;
        swapRouter = params.swapRouter;
    }

    function claimAndDonateRewards(address token, uint256 minimumAmountOut) external returns (uint256) {
        IFarmingPool(token).claim();

        // Amount of reward token claimed plus any sent to this contract from grants.
        uint256 amountRewardToken = IERC20(rewardToken).balanceOf(address(this));

        if (amountRewardToken == 0) return 0;

        //TODO figure out a route on arbitrum ARB -> ??? -> alETH
        IVelodromeSwapRouter.route[] memory routes = new IVelodromeSwapRouter.route[](1);
        routes[0] = IVelodromeSwapRouter.route(0x4200000000000000000000000000000000000042, 0x3E29D3A9316dAB217754d13b28646B76607c5f04, false);
        TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardToken);
        IVelodromeSwapRouter(swapRouter).swapExactTokensForTokens(amountRewardToken, minimumAmountOut, routes, address(this), block.timestamp);


         // Donate to alchemist depositors
        uint256 debtReturned = IERC20(alAsset).balanceOf(address(this));
        TokenUtils.safeApprove(alAsset, alchemist, debtReturned);
        IAlchemistV2(alchemist).donate(token, debtReturned);

        return amountRewardToken;
    }

    function getExpectedExchange(address farmToken) external view returns (uint256) {
        uint256 expectedExchange;
        // TODO: Update this to use the correct Gearbox reward distributor interface
        uint256 claimable = IFarmingPool(gearboxRewardDistributor).farmed(address(this));
        uint256 totalToSwap = claimable + TokenUtils.safeBalanceOf(rewardToken, address(this));

        if (alAsset == alEthArbitrum) {
            expectedExchange = totalToSwap * uint(IChainlinkOracle(arbToUsdOracle).latestAnswer()) / uint(IChainlinkOracle(ethToUsdOracle).latestAnswer());
        } else {
            revert IllegalState("Invalid alAsset");
        }

        return expectedExchange;
    }
}