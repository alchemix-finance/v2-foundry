// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract TestTransmuter {
    mapping(address => uint256) public totalExchanged;

    function onERC20Received(address token, uint256 amount) external {
        totalExchanged[token] += amount;
    }
}