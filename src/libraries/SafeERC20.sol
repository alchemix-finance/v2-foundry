// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import {IllegalState} from "../base/Errors.sol";
import "forge-std/console.sol";

/// @title  SafeERC20
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/SafeTransferLib.sol)
/// @author Alchemix Finance
library SafeERC20 {
    /// @dev Expects the token to return the number of decimals that it uses.
    ///
    /// @param token The address of the token.
    ///
    /// @return The number of decimals that the token has.
    function expectDecimals(address token) internal view returns (uint256) {
        bool status;
        assembly {
            let pointer := mload(0x40)

            mstore(pointer, 0x313ce56700000000000000000000000000000000000000000000000000000000)

            status := staticcall(gas(), token, pointer, 4, 0, 32)
        }

        (uint256 decimals, bool success) = expectUInt256Response(status);
        if (!success) {
            revert IllegalState("Decimals call malformed response");
        }

        return decimals;
    }

    /// @dev Safely sets an allowance.
    ///
    /// @param token   The address of the token.
    /// @param spender The address to allow to transfer tokens.
    /// @param value   The amount of tokens to allow to be transferred.
    function safeApprove(address token, address spender, uint256 value) internal {
        bool status;
        assembly {
            let pointer := mload(0x40)

            mstore(pointer, 0x095ea7b300000000000000000000000000000000000000000000000000000000)
            mstore(add(pointer,  4), and(spender, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(pointer, 36), value)

            status := call(gas(), token, 0, pointer, 68, 0, 32)
        }

        if (!checkBooleanResponse(status)) {
            revert IllegalState("Expected approval to succeed");
        }
    }

    /// @dev Safely transfers tokens from an address to another.
    ///
    /// @param token    The address of the token.
    /// @param receiver The address to transfer tokens to.
    /// @param amount   The amount of tokens to transfer.
    function safeTransfer(address token, address receiver, uint256 amount) internal {
        bool status;
        assembly {
            let pointer := mload(0x40)

            mstore(pointer, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(pointer,  4), and(receiver, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(pointer, 36), amount)

            status := call(gas(), token, 0, pointer, 68, 0, 32)
        }

        if (!checkBooleanResponse(status)) {
            revert IllegalState("Expected transfer to succeed");
        }
    }

    /// @dev Safely transfers tokens from an address to another using an allowance.
    ///
    /// @param token    The address of the token.
    /// @param owner    The address to transfer tokens from.
    /// @param receiver The address to transfer tokens to.
    /// @param amount   The amount of tokens to transfer.
    function safeTransferFrom(
        address token,
        address owner,
        address receiver,
        uint256 amount
    ) internal {
        bool status;
        assembly {
            let pointer := mload(0x40)

            mstore(pointer, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(pointer,  4), and(owner,    0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(pointer, 36), and(receiver, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(pointer, 68), amount)

            status := call(gas(), token, 0, pointer, 100, 0, 32)
        }

        if (!checkBooleanResponse(status)) {
            revert IllegalState("Expected transfer from to succeed");
        }
    }

    /// @dev Checks the call response and gets if the call was successful.
    ///
    /// When a call is unsuccessful the return data is expected to be error data. The data is
    /// rethrown to bubble up the error to the caller.
    ///
    /// When a call is successful it is expected that the return data is empty or greater than 31
    /// bytes in length and the value returned is exactly equal to 1.
    ///
    /// @param status A flag indicating if the call has reverted or not.
    ///
    /// @return success If the call was successful.
    function checkBooleanResponse(bool status) private pure returns (bool success) {
        assembly {
            if iszero(status) {
                returndatacopy(0, 0, returndatasize())

                revert(0, returndatasize())
            }

            success := or(
            and(eq(mload(0), 1), gt(returndatasize(), 31)),
            iszero(returndatasize())
            )
        }
    }

    /// @dev Checks that the call responded with a 256 bit integer.
    ///
    /// When a call is unsuccessful the return data is expected to be error data. The data is
    /// rethrown to bubble up the error to the caller.
    ///
    /// When a call is successful it is expected that the return data is exactly 32 bytes in
    /// length. Any other return size is treated as an error. When the return data is non-empty,
    /// it is expected that the return data is a unsigned 256 bit integer.
    ///
    /// @param status A flag indicating if the call has reverted or not.
    ///
    /// @return value   The returned 256 bit integer value.
    /// @return success If the call was successful.
    function expectUInt256Response(bool status) private pure returns (uint256 value, bool success) {
        assembly {
            if iszero(status) {
                returndatacopy(0, 0, returndatasize())

                revert(0, returndatasize())
            }

            switch gt(returndatasize(), 31)
            case 1 {
                value   := mload(0)
                success := 1
            }
            default {
                success := 0
            }
        }
    }
}