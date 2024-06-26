// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

library FarmAccounting {
    error ZeroDuration();
    error DurationTooLarge();
    error AmountTooLarge();

    struct Info {
        uint40 finished;
        uint32 duration;
        uint184 reward;
        uint256 balance;
    }

    uint256 internal constant _MAX_REWARD_AMOUNT = 1e32;  // 108 bits
    uint256 internal constant _SCALE = 1e18;  // 60 bits

    /// @dev Requires extra 18 decimals for precision, result fits in 168 bits
    function farmedSinceCheckpointScaled(Info storage info, uint256 checkpoint) internal view returns(uint256 amount) {
        unchecked {
            (uint40 finished, uint32 duration, uint184 reward) = (info.finished, info.duration, info.reward);
            if (duration > 0) {
                uint256 elapsed = Math.min(block.timestamp, finished) - Math.min(checkpoint, finished);
                // size of (type(uint32).max * _MAX_REWARD_AMOUNT * _SCALE) is less than 200 bits, so there is no overflow
                return elapsed * reward * _SCALE / duration;
            }
        }
    }

    function startFarming(Info storage info, uint256 amount, uint256 period) internal returns(uint256) {
        if (period == 0) revert ZeroDuration();
        if (period > type(uint32).max) revert DurationTooLarge();

        // If something left from prev farming add it to the new farming
        (uint40 finished, uint32 duration, uint184 reward, uint256 balance) = (info.finished, info.duration, info.reward, info.balance);
        if (block.timestamp < finished) {
            amount += reward - farmedSinceCheckpointScaled(info, finished - duration) / _SCALE;
        }

        if (amount > _MAX_REWARD_AMOUNT) revert AmountTooLarge();

        (info.finished, info.duration, info.reward, info.balance) = (
            uint40(block.timestamp + period),
            uint32(period),
            uint184(amount),
            balance + amount
        );
        return amount;
    }

    function stopFarming(Info storage info) internal returns(uint256 leftover) {
        leftover = info.reward - farmedSinceCheckpointScaled(info, info.finished - info.duration) / _SCALE;
        (info.finished, info.duration, info.reward, info.balance) = (
            uint40(block.timestamp),
            uint32(0),
            uint184(0),
            info.balance - leftover
        );
    }

    function claim(Info storage info, uint256 amount) internal {
        info.balance -= amount;
    }
}