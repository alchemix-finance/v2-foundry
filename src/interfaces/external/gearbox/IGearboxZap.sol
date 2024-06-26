// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGearboxZap {
    function zapIn(uint256 amount, address onBehalfOf, uint256 minLPAmount) external returns (uint256);
    function zapOut(uint256 lpAmount, address onBehalfOf, uint256 minAmount) external returns (uint256);
}