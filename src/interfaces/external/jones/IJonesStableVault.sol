// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

interface IJonesStableVault {
    function convertToAssets(uint256 amount) external view returns (uint256);
}