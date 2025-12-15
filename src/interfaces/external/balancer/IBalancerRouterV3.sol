// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRouter {
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256 amountOut);

    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 maxAmountIn,
        uint256 exactAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256 amountIn);
}

contract BalancerV3Swapper {
    using SafeERC20 for IERC20;

    IRouter public immutable router;

    constructor(IRouter _router) {
        router = _router;
    }

    function swapExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 minOut
    ) external returns (uint256 amountOut) {
        // 1) pull funds into this contract (router will debit msg.sender = this contract)
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);

        // 2) approve router
        tokenIn.safeIncreaseAllowance(address(router), amountIn);

        // 3) swap (userData usually empty; deadline typical)
        amountOut = router.swapSingleTokenExactIn(
            pool,
            tokenIn,
            tokenOut,
            amountIn,
            minOut,
            block.timestamp + 60,
            false,          // set true only if you want native ETH wrap/unwrap behavior
            bytes("")
        );

        // 4) pay user
        tokenOut.safeTransfer(msg.sender, amountOut);
    }
}