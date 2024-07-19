// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

/// @title IJonesDaoVaultRouter
interface IJonesDaoVaultRouter {
    function rewardCompounder(address _asset) external view returns (address);

    function stableWithdrawalSignal(uint256 _shares, bool _compound) external;

    function deposit(uint256 _assets, address _receiver) external returns (uint256);

    function withdrawRequest(uint256 _shares, address _receiver, uint256 _minAmountOut, bytes calldata _enforceData) external returns (bool, uint256);
}