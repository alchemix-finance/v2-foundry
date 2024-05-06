// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

interface IJonesDaoGlpVault {
    function depositStable(uint256 _assets,bool _compound) external returns (uint256);
}