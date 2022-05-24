// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IConvexRewards {
    function rewardToken() external view returns (IERC20);
    function earned(address account) external view returns (uint256);
    function extraRewards(uint256 index) external view returns (address);
    function balanceOf(address account) external returns(uint256);
    function withdraw(uint256 amount, bool claim) external returns (bool);
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);
    function getReward() external returns (bool);
    function getReward(address recipient, bool claim) external returns (bool);
    function stake(uint256 amount) external returns (bool);
    function stakeFor(address account, uint256 amount) external returns (bool);
}