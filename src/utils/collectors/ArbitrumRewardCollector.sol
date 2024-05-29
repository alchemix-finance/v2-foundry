pragma solidity ^0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../../interfaces/IAlchemistV2.sol";
import {ISwapRouter} from "../../interfaces/external/ramses/ISwapRouter.sol";
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
    address constant AAVE_INCENTIVES = 0x929EC64c34a17401F460460D4B9390518E5B473e;
    address constant ALUSD = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address constant ALETH = 0x3E29D3A9316dAB217754d13b28646B76607c5f04;
    address constant ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address constant FRAX = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

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
            inputs[0] = abi.encode(address(this), uint256(2000000000000000000), uint256(0), abi.encodePacked(ARB, uint24(500), USDC), true);
            ISwapRouter(swapRouter).execute(abi.encodePacked(uint8(0)), inputs);

            inputs[0] = abi.encode(address(this), IERC20(USDC).balanceOf(address(this)), uint256(0), [USDC,ALUSD], true);
            ISwapRouter(swapRouter).execute(abi.encodePacked(uint8(8)), inputs);
        } else if (debtToken == 0x17573150d67d820542EFb24210371545a4868B03) {
            TokenUtils.safeApprove(rewardToken, swapRouter, amountRewardToken);

            bytes[] memory inputs =  new bytes[](1);
            inputs[0] = abi.encode(address(this), uint256(2000000000000000000), uint256(0), abi.encodePacked(ARB, uint24(500), USDC), true);
            ISwapRouter(swapRouter).execute(abi.encodePacked(uint8(0)), inputs);

            inputs[0] = abi.encode(address(this), IERC20(USDC).balanceOf(address(this)), uint256(0), [USDC,ALUSD], true);
            ISwapRouter(swapRouter).execute(abi.encodePacked(uint8(8)), inputs);
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
        if (debtToken == ALUSD) {

        } else if (debtToken == ALETH) {

        } else {
            revert IllegalState("Invalid debt token");
        }

        return expectedExchange;
    }
}