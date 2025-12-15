// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IllegalArgument, IllegalState, Unauthorized} from "../../base/ErrorMessages.sol";
import {MutexLock} from "../../base/MutexLock.sol";

import {SafeERC20} from "../../libraries/SafeERC20.sol";

import {IChainlinkOracle} from "../../interfaces/external/chainlink/IChainlinkOracle.sol";
import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";
import {IStETH} from "../../interfaces/external/lido/IStETH.sol";
import {IWstETH} from "../../interfaces/external/lido/IWstETH.sol";
import {ISwapRouter} from "../../interfaces/external/uniswap/ISwapRouter.sol";

struct InitializationParams {
    address alchemist;
    address token;
    address underlyingToken;
    address oracleWstethEth;
    address router;
}

contract WstETHAdapterArbitrum is ITokenAdapter, MutexLock {
    string public override version = "1.1.0";

    address public immutable alchemist;
    address public immutable override token;
    address public immutable override underlyingToken;
    address public immutable oracleWstethEth;
    address public immutable router;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        token           = params.token;
        underlyingToken = params.underlyingToken;
        oracleWstethEth = params.oracleWstethEth;
        router          = params.router;
    }

    /// @dev Checks that the message sender is the alchemist that the adapter is bound to.
    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert Unauthorized("Not alchemist");
        }
        _;
    }

    receive() external payable {
        if (msg.sender != underlyingToken && msg.sender != router) {
            revert Unauthorized("Payments only permitted from WETH or curve pool");
        }
    }

    /// @inheritdoc ITokenAdapter
    function price() external view returns (uint256) {
        // Ensure that round is complete, otherwise price is stale.
        (
            uint80 roundID,
            int256 wstethToEth,
            ,
            uint256 updateTime,
            uint80 answeredInRound
        ) = IChainlinkOracle(oracleWstethEth).latestRoundData();
        require(
            answeredInRound >= roundID,
            "Chainlink Price Stale"
        );

        require(wstethToEth > 0, "Chainlink Malfunction");
        require(updateTime != 0, "Incomplete round");

        if( updateTime < block.timestamp - 86400 seconds ) {
            revert("Stale Price");
        }

        // Note that an oracle attack could push the price of stETH over 1 ETH, which could lead to alETH minted at a LTV ratio > 50%. 
        // Additionally, if stETH price is pushed > 2 ETH, then unbacked alETH could be minted. 
        // We cap the steth oracel price at 1 for this reason.
        if (wstethToEth > 2e18) wstethToEth = 2e18;

        return uint256(wstethToEth);
    }

    /// @inheritdoc ITokenAdapter
    function wrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the tokens from the message sender.
        SafeERC20.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        // Swap WETH to wstETH
        SafeERC20.safeApprove(underlyingToken, address(router), amount);

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: underlyingToken,
                tokenOut: token,
                fee: 100,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        ISwapRouter(router).exactInputSingle(params);

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        SafeERC20.safeTransfer(token, recipient, balanceAfter - balanceBefore);

        return balanceAfter - balanceBefore;
    }

    // @inheritdoc ITokenAdapter
    function unwrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the tokens from the message sender.
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);

        SafeERC20.safeApprove(token, address(router), amount);

        uint256 balanceBefore = IERC20(underlyingToken).balanceOf(address(this));

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: token,
                tokenOut: underlyingToken,
                fee: 100,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        ISwapRouter(router).exactInputSingle(params);

        uint256 balanceAfter = IERC20(underlyingToken).balanceOf(address(this));

        SafeERC20.safeTransfer(underlyingToken, recipient, balanceAfter - balanceBefore);

        return balanceAfter - balanceBefore;
    }
}