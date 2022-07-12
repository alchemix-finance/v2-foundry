pragma solidity ^0.8.13;

import {IllegalArgument} from "../base/Errors.sol";

/// @title  Functions
/// @author Alchemix Finance
library Limiters {
    using Limiters for LinearGrowthLimiter;

    /// @dev A maximum cooldown to avoid malicious governance bricking the contract.
    /// @dev 1 day @ 12 sec / block
    uint256 constant public MAX_COOLDOWN_BLOCKS = 1 days / 12 seconds;

    /// @dev The scalar used to convert integral types to fixed point numbers.
    uint256 constant public FIXED_POINT_SCALAR = 1e18;

    /// @dev The configuration and state of a linear growth function (LGF).
    struct LinearGrowthLimiter {
        uint256 maximum;        /// The maximum limit of the function.
        uint256 rate;           /// The rate at which the function increases back to its maximum.
        uint256 lastValue;      /// The most recently saved value of the function.
        uint256 lastBlock;      /// The block that `lastValue` was recorded.
        uint256 minLimit;       /// A minimum limit to avoid malicious governance bricking the contract
    }

    /// @dev Instantiates a new linear growth function.
    ///
    /// @param maximum The maximum value for the LGF.
    /// @param blocks  The number of blocks that determines the rate of the LGF.
    /// @param _minLimit The new minimum limit of the LGF.
    ///
    /// @return The LGF struct.
    function createLinearGrowthLimiter(uint256 maximum, uint256 blocks, uint256 _minLimit) internal view returns (LinearGrowthLimiter memory) {
        if (blocks > MAX_COOLDOWN_BLOCKS) {
            revert IllegalArgument();
        }

        if (maximum < _minLimit) {
            revert IllegalArgument();
        }

        return LinearGrowthLimiter({
            maximum: maximum,
            rate: maximum * FIXED_POINT_SCALAR / blocks,
            lastValue: maximum,
            lastBlock: block.number,
            minLimit: _minLimit
        });
    }

    /// @dev Configure an LGF.
    ///
    /// @param self    The LGF to configure.
    /// @param maximum The maximum value of the LFG.
    /// @param blocks  The number of recovery blocks of the LGF.
    function configure(LinearGrowthLimiter storage self, uint256 maximum, uint256 blocks) internal {
        if (blocks > MAX_COOLDOWN_BLOCKS) {
            revert IllegalArgument();
        }

        if (maximum < self.minLimit) {
            revert IllegalArgument();
        }

        if (self.lastValue > maximum) {
            self.lastValue = maximum;
        }

        self.maximum = maximum;
        self.rate = maximum * FIXED_POINT_SCALAR / blocks;
    }

    /// @dev Updates the state of an LGF by updating `lastValue` and `lastBlock`.
    ///
    /// @param self the LGF to update.
    function update(LinearGrowthLimiter storage self) internal {
        self.lastValue = self.get();
        self.lastBlock = block.number;
    }

    /// @dev Increase the value of the linear growth limiter.
    ///
    /// @param self   The linear growth limiter.
    /// @param amount The amount to decrease `lastValue`.
    function increase(LinearGrowthLimiter storage self, uint256 amount) internal {
        uint256 value = self.get();
        self.lastValue = value + amount;
        self.lastBlock = block.number;
    }

    /// @dev Decrease the value of the linear growth limiter.
    ///
    /// @param self   The linear growth limiter.
    /// @param amount The amount to decrease `lastValue`.
    function decrease(LinearGrowthLimiter storage self, uint256 amount) internal {
        uint256 value = self.get();
        self.lastValue = value - amount;
        self.lastBlock = block.number;
    }

    /// @dev Get the current value of the linear growth limiter.
    ///
    /// @return The current value.
    function get(LinearGrowthLimiter storage self) internal view returns (uint256) {
        uint256 elapsed = block.number - self.lastBlock;
        if (elapsed == 0) {
            return self.lastValue;
        }
        uint256 delta = elapsed * self.rate / FIXED_POINT_SCALAR;
        uint256 value = self.lastValue + delta;
        return value > self.maximum ? self.maximum : value;
    }
}