// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title  Multicall interface
/// @author Uniswap Labs
///
/// @notice Enables calling multiple methods in a single call to the contract.
/// @dev    The use of `msg.value` should be heavily scrutinized for implementors of this interfaces.
interface IMulticall {
    /// @notice An error used to indicate that an individual call in a multicall failed.
    ///
    /// @param data   The call data.
    /// @param result The result of the call.
    error MulticallFailed(bytes data, bytes result);

    /// @notice Call multiple functions in the implementing contract.
    ///
    /// @param data The encoded function data for each of the calls to make to this contract.
    ///
    /// @return results The results from each of the calls passed in via data.
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
}