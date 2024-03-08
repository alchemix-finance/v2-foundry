// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

/// @title IJonesDaoVaultRouter
interface IJonesDaoVaultRouter {
    function rewardCompounder(address _asset) external view returns (address);

    function stableWithdrawalSignal(uint256 _shares, bool _compound) external;
}