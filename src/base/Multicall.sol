// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.11;

import "../interfaces/IMulticall.sol";

/// @title  Multicall
/// @author Uniswap Labs
///
/// @notice Enables calling multiple methods in a single call to the contract
abstract contract Multicall is IMulticall {
    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata data) external payable override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                revert MulticallFailed(data[i], result);
            }

            results[i] = result;
        }
    }
}