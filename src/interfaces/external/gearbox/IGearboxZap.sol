// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGearboxZap {
    function deposit(uint256, address) external returns (uint256 tokenOutAmount);
    function redeem(uint256, address) external returns (uint256 tokenOutAmount);
}