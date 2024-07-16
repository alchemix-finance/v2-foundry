pragma solidity ^0.8.13;

import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { TokenUtils } from "../../libraries/TokenUtils.sol";

import { IAlchemistV2 } from "../../interfaces/IAlchemistV2.sol";
import { IERC4626 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
// TODO: Import the correct interface for Gearbox farming token
import { IFarmingPool } from "../../interfaces/external/gearbox/IFarmingPool.sol";
// TODO: Import the correct interface for Gearbox reward distributor
import { ISwapRouter, ISwapRouterv2, V2Pool, RamsesQuote, QuoteExactInputSingleV3Params, route } from "../../interfaces/external/ramses/ISwapRouter.sol";
import { IChainlinkOracle } from "../../interfaces/external/chainlink/IChainlinkOracle.sol";

import { IRewardCollector } from "../../interfaces/IRewardCollector.sol";
import { Unauthorized, IllegalState, IllegalArgument } from "../../base/ErrorMessages.sol";

struct InitializationParams {
	address alchemist;
	address debtToken;
	address rewardToken;
	address swapRouter;
}

/// @title GearboxRewardCollector
/// @author Alchemix Finance
contract GearboxRewardCollector is IRewardCollector {
    // arb ETH rewards distributor address
    // address constant gearboxRewardDistributor = 0xf3b7994e4dA53E04155057Fd61dc501599d57877;
	//arb USDC rewards distributor address
	// address constant gearboxRewardDistributor = 0xD0181a36B0566a8645B7eECFf2148adE7Ecf2BE9;
	address constant ALUSD = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
	address constant ALETH = 0x17573150d67d820542EFb24210371545a4868B03;
	address constant FRAX = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
	address constant FRAXETH = 0x178412e79c25968a32e89b11f63B33F733770c2A;
	address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
	address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
	address constant RamsesRouter = 0xAAA87963EFeB6f7E0a2711F397663105Acb1805e;
	address constant arbToUsdOracle = 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6;
	address constant ethToUsdOracle = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
	uint256 constant FIXED_POINT_SCALAR = 1e18;
	uint256 constant BPS = 10000;
	string public override version = "1.0.0";
	address public alchemist;
	address public debtToken;
	address public override rewardToken;
	address public override swapRouter;

	constructor(InitializationParams memory params) {
		alchemist = params.alchemist;
		debtToken = params.debtToken;
		rewardToken = params.rewardToken;
		swapRouter = params.swapRouter;
	}

	function claimAndDonateRewards(address token, uint256 minimumAmountOut) external returns (uint256) {
		IFarmingPool(token).claim();

		// Amount of reward token claimed plus any sent to this contract from grants.
		uint256 amountRewardToken = IERC20(rewardToken).balanceOf(address(this));

		if (amountRewardToken == 0) return 0;
        //swap arb to alusd
		if (debtToken == ALUSD) {
			TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardToken);
			bytes[] memory inputs = new bytes[](1);
			inputs[0] = abi.encode(
				address(this),
				amountRewardToken,
				uint256(0),
				abi.encodePacked(rewardToken, uint24(500), USDC),
				true
			);
			ISwapRouter(swapRouter).execute(abi.encodePacked(uint8(0)), inputs);

			TokenUtils.safeApprove(USDC, swapRouter, IERC20(USDC).balanceOf(address(this)));
			inputs[0] = abi.encode(
				address(this),
				IERC20(USDC).balanceOf(address(this)),
				uint256(0),
				abi.encodePacked(USDC, uint24(100), FRAX),
				true
			);
			ISwapRouter(swapRouter).execute(abi.encodePacked(uint8(0)), inputs);

			TokenUtils.safeApprove(
				FRAX,
				RamsesRouter,
				IERC20(FRAX).balanceOf(address(this))
			);
			route[] memory routes = new route[](1);
			routes[0] = route(FRAX, ALUSD, true);
			ISwapRouterv2(RamsesRouter).swapExactTokensForTokens(
				IERC20(FRAX).balanceOf(address(this)),
				minimumAmountOut,
				routes,
				address(this),
				block.timestamp
			);
        //swap arb to aleth
		} else if (debtToken == ALETH) {
			TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardToken);
			bytes[] memory inputs = new bytes[](1);
			inputs[0] = abi.encode(
				address(this),
				amountRewardToken,
				uint256(0),
				abi.encodePacked(rewardToken, uint24(500), WETH),
				true
			);
			ISwapRouter(swapRouter).execute(abi.encodePacked(uint8(0)), inputs);

			TokenUtils.safeApprove(
				WETH,
				RamsesRouter,
				IERC20(WETH).balanceOf(address(this))
			);
			route[] memory routes = new route[](1);
			routes[0] = route(WETH, FRAXETH, true);
			ISwapRouterv2(RamsesRouter).swapExactTokensForTokens(
				IERC20(WETH).balanceOf(address(this)),
				0,
				routes,
				address(this),
				block.timestamp
			);

			TokenUtils.safeApprove(
				FRAXETH,
				RamsesRouter,
				IERC20(FRAXETH).balanceOf(address(this))
			);
			routes[0] = route(FRAXETH, ALETH, true);
			ISwapRouterv2(RamsesRouter).swapExactTokensForTokens(
				IERC20(FRAXETH).balanceOf(address(this)),
				minimumAmountOut,
				routes,
				address(this),
				block.timestamp
			);
		} else {
			revert IllegalState("Reward collector `debtToken` is not supported");
		}

		// Donate to alchemist depositors
		uint256 debtReturned = IERC20(debtToken).balanceOf(address(this));
		TokenUtils.safeApprove(debtToken, alchemist, debtReturned);
		IAlchemistV2(alchemist).donate(token, debtReturned);

		return amountRewardToken;
	}

	function getExpectedExchange(address token) external view returns (uint256) {
		uint256 expectedExchange;
		uint256 claimable = IFarmingPool(token).farmed(address(this));
		uint256 totalToSwap = claimable + TokenUtils.safeBalanceOf(rewardToken, address(this));

		if (debtToken == ALETH) {
			expectedExchange =
				(totalToSwap * uint(IChainlinkOracle(arbToUsdOracle).latestAnswer())) /
				uint(IChainlinkOracle(ethToUsdOracle).latestAnswer());
		} else if (debtToken == ALUSD) {
            expectedExchange = (totalToSwap * uint(IChainlinkOracle(arbToUsdOracle).latestAnswer()));
        }else {
			revert IllegalState("Invalid alAsset");
		}

		return expectedExchange;
	}
}
