// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract ERC20User {
    IERC20 private token;

    constructor(IERC20 _token) {
        token = _token;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return token.approve(spender, amount);
    }

    function transfer(address receiver, uint256 amount) external returns (bool) {
        return token.transfer(receiver, amount);
    }

    function transferFrom(address owner, address receiver, uint256 amount) external returns (bool) {
        return token.transferFrom(owner, receiver, amount);
    }
}
