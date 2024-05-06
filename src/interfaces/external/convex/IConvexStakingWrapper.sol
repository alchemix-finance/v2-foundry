// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IConvexStakingWrapper {
    function deposit(uint256 amount, address to) external;
    function withdraw(uint256 amount) external;
    function withdrawAndUnwrap(uint256 _amount) external;
}