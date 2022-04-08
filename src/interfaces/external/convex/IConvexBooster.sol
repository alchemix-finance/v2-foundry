// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IConvexBooster {
    function deposit(uint256 pid, uint256 amount, bool stake) external returns (bool);
    function withdraw(uint256 pid, uint256 amount) external returns (bool);
}