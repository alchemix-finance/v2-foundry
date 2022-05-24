// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IStETH is IERC20 {
    function sharesOf(address account) external view returns (uint256);
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
    function submit(address referral) external payable returns (uint256);
}