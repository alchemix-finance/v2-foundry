// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;


interface IVelodromeSwapRouterV2 {
    struct route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}