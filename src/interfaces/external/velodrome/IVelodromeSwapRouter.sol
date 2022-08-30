// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;


interface IVelodromeSwapRouter {
    struct route {
        address from;
        address to;
        bool stable;
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}