// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

/// @title  Mutex
/// @author Alchemix Finance
///
/// @notice Provides a mutual exclusion lock for implementing contracts.
abstract contract Mutex {
    /// @notice An error which is thrown when a lock is attempted to be claimed before it has been freed.
    error LockAlreadyClaimed();

    /// @notice The lock state. Non-zero values indicate the lock has been claimed.
    uint256 private _lockState;

    /// @dev A modifier which acquires the mutex.
    modifier lock() {
        _claimLock();

        _;

        _freeLock();
    }

    /// @dev Gets if the mutex is locked.
    ///
    /// @return if the mutex is locked.
    function _isLocked() internal returns (bool) {
        return _lockState == 1;
    }

    /// @dev Claims the lock. If the lock is already claimed, then this will revert.
    function _claimLock() internal {
        // Check that the lock has not been claimed yet.
        if (_lockState != 0) {
            revert LockAlreadyClaimed();
        }

        // Claim the lock.
        _lockState = 1;
    }

    /// @dev Frees the lock.
    function _freeLock() internal {
        _lockState = 0;
    }
}