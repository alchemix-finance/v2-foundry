// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title IJGLPViewer
interface IJGLPViewer {
    function getUSDCRedemption(uint256 _jUSDC, address _caller) external view returns (uint256, uint256);
}