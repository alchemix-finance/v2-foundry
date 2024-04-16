// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IConvexFraxBooster {
    function createVault(uint256 _pid) external returns (address);
}