// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {SafeERC20} from "../../../libraries/SafeERC20.sol";

contract SafeERC20User {
    IERC20 public token;

    constructor(IERC20 _token) {
        token = _token;
    }

    function expectDecimals(address token) external view returns (uint256) {
        return SafeERC20.expectDecimals(token);
    }

    function safeApprove(address spender, uint256 value) external {
        SafeERC20.safeApprove(address(token), spender, value);
    }

    function safeTransfer(address receiver, uint256 amount) external {
        SafeERC20.safeTransfer(address(token), receiver, amount);
    }

    function safeTransferFrom(
        address owner,
        address receiver,
        uint256 amount
    ) external {
        SafeERC20.safeTransferFrom(address(token), owner, receiver, amount);
    }
}
