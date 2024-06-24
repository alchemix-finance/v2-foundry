pragma solidity ^0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../../interfaces/IAlchemistV2.sol";

import {
    ISwapRouter, 
    ISwapRouterv2, 
    V2Pool,
    RamsesQuote,
    QuoteExactInputSingleV3Params, 
    route
} from "../../interfaces/external/ramses/ISwapRouter.sol";

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

/// @title  ArbitrumRewardCollector
/// @author Alchemix Finance
contract ArbitrumRewardCollector is IRewardCollector, Ownable {
    address constant ALUSD = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address constant ALETH = 0x17573150d67d820542EFb24210371545a4868B03;
    address constant FRAX = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address constant FRAXETH = 0x178412e79c25968a32e89b11f63B33F733770c2A;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    uint256 constant FIXED_POINT_SCALAR = 1e18;
    string public override version = "1.0.0";
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
            TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardToken);
            bytes[] memory inputs =  new bytes[](1);
            inputs[0] = abi.encode(address(this), amountRewardToken, uint256(0), abi.encodePacked(rewardToken, uint24(500), USDC), true);
            ISwapRouter(swapRouter).execute(abi.encodePacked(uint8(0)), inputs);

            TokenUtils.safeApprove(USDC, swapRouter, IERC20(USDC).balanceOf(address(this)));
            inputs[0] = abi.encode(address(this), IERC20(USDC).balanceOf(address(this)), uint256(0), abi.encodePacked(USDC, uint24(100), FRAX), true);
            ISwapRouter(swapRouter).execute(abi.encodePacked(uint8(0)), inputs);

            TokenUtils.safeApprove(FRAX, 0xAAA87963EFeB6f7E0a2711F397663105Acb1805e, IERC20(FRAX).balanceOf(address(this)));
            route[] memory routes = new route[](1);
            routes[0] = route(FRAX, ALUSD, true);
            ISwapRouterv2(0xAAA87963EFeB6f7E0a2711F397663105Acb1805e).swapExactTokensForTokens(IERC20(FRAX).balanceOf(address(this)), minimumAmountOut, routes, address(this), block.timestamp);
        } else if (debtToken == 0x17573150d67d820542EFb24210371545a4868B03) {
            TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardToken);
            bytes[] memory inputs =  new bytes[](1);
            inputs[0] = abi.encode(address(this), amountRewardToken, uint256(0), abi.encodePacked(rewardToken, uint24(500), WETH), true);
            ISwapRouter(swapRouter).execute(abi.encodePacked(uint8(0)), inputs);

            TokenUtils.safeApprove(WETH, 0xAAA87963EFeB6f7E0a2711F397663105Acb1805e, IERC20(WETH).balanceOf(address(this)));
            route[] memory routes = new route[](1);
            routes[0] = route(WETH, FRAXETH, true);
            ISwapRouterv2(0xAAA87963EFeB6f7E0a2711F397663105Acb1805e).swapExactTokensForTokens(IERC20(WETH).balanceOf(address(this)), 0, routes, address(this), block.timestamp);
            
            TokenUtils.safeApprove(FRAXETH, 0xAAA87963EFeB6f7E0a2711F397663105Acb1805e, IERC20(FRAXETH).balanceOf(address(this)));
            routes[0] = route(FRAXETH, ALETH, true);
            ISwapRouterv2(0xAAA87963EFeB6f7E0a2711F397663105Acb1805e).swapExactTokensForTokens(IERC20(FRAXETH).balanceOf(address(this)), minimumAmountOut, routes, address(this), block.timestamp);
        } else {
            revert IllegalState("Reward collector `debtToken` is not supported");
        }

        // Donate to alchemist depositors
        uint256 debtReturned = IERC20(debtToken).balanceOf(address(this));
        TokenUtils.safeApprove(debtToken, alchemist, debtReturned);
        IAlchemistV2(alchemist).donate(token, debtReturned);

        return amountRewardToken;
    }

    function getExpectedExchange() external returns (uint256) {
        uint256 totalToSwap = TokenUtils.safeBalanceOf(rewardToken, address(this));

        // Find expected amount out before calling harvest
        if (debtToken == ALUSD) {
            // QuoteExactInputSingleV3Params memory params = QuoteExactInputSingleV3Params(rewardToken, USDC, totalToSwap, uint24(500), uint160(0));
            // (uint256 arbToUsdc, , , ) = RamsesQuote(0xAA29F3218E72974FE7Ce81b0826273FEA12cbF3C).quoteExactInputSingleV3(params);
            
            // params = QuoteExactInputSingleV3Params(USDC, FRAX, arbToUsdc, uint24(100), uint160(0));
            // (uint256 usdcToFrax, , , ) = RamsesQuote(0xAA29F3218E72974FE7Ce81b0826273FEA12cbF3C).quoteExactInputSingleV3(params);

            // return(V2Pool(0xfd599DB360Cd9713657C95dF66650A427d213010).getAmountOut(usdcToFrax, FRAX));

            return 0;
        } else if (debtToken == ALETH) {
            // QuoteExactInputSingleV3Params memory params = QuoteExactInputSingleV3Params(rewardToken, WETH, totalToSwap, uint24(500), uint160(0));
            // (uint256 arbToWETH, , , ) = RamsesQuote(0xAA29F3218E72974FE7Ce81b0826273FEA12cbF3C).quoteExactInputSingleV3(params);
            
            // uint256 wethToFraxeth =  V2Pool(0x3932192dE4f17DFB94Be031a8458E215A44BF560).getAmountOut(arbToWETH, WETH);

            // return(V2Pool(0xfB4fE921F724f3C7B610a826c827F9F6eCEf6886).getAmountOut(wethToFraxeth, FRAXETH));

            return 0;
        } else {
            revert IllegalState("Invalid debt token");
        }
    }
}