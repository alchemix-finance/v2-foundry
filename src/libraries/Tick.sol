// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

import {FixedPointMath} from "./FixedPointMath.sol";

library Tick {
  using FixedPointMath for FixedPointMath.Number;

  struct Info {
    // The total number of unexchanged tokens that have been associated with this tick
    uint256 totalBalance;
    // The accumulated weight of the tick which is the sum of the previous ticks accumulated weight plus the weight
    // that added at the time that this tick was created
    FixedPointMath.Number accumulatedWeight;
    // The previous active node. When this value is zero then there is no predecessor
    uint256 prev;
    // The next active node. When this value is zero then there is no successor
    uint256 next;
  }

  struct Cache {
    // The mapping which specifies the ticks in the buffer
    mapping(uint256 => Info) values;
    // The current tick which is being written to
    uint256 position;
    // The first tick which will be examined when iterating through the queue
    uint256 head;
    // The last tick which new nodes will be appended after
    uint256 tail;
  }

  /// @dev Gets the next tick in the buffer.
  ///
  /// This increments the position in the buffer.
  ///
  /// @return The next tick.
  function next(Tick.Cache storage self) internal returns (Tick.Info storage) {
    ++self.position;
    return self.values[self.position];
  }

  /// @dev Gets the current tick being written to.
  ///
  /// @return The current tick.
  function current(Tick.Cache storage self) internal view returns (Tick.Info storage) {
    return self.values[self.position];
  }

  /// @dev Gets the nth tick in the buffer.
  ///
  /// @param self The reference to the buffer.
  /// @param n    The nth tick to get.
  function get(Tick.Cache storage self, uint256 n) internal view returns (Tick.Info storage) {
    return self.values[n];
  }

  function getWeight(
    Tick.Cache storage self,
    uint256 from,
    uint256 to
  ) internal view returns (FixedPointMath.Number memory) {
    Tick.Info storage startingTick = self.values[from];
    Tick.Info storage endingTick = self.values[to];

    FixedPointMath.Number memory startingAccumulatedWeight = startingTick.accumulatedWeight;
    FixedPointMath.Number memory endingAccumulatedWeight = endingTick.accumulatedWeight;

    return endingAccumulatedWeight.sub(startingAccumulatedWeight);
  }

  function addLast(Tick.Cache storage self, uint256 id) internal {
    if (self.head == 0) {
      self.head = self.tail = id;
      return;
    }

    // Don't add the tick if it is already the tail. This has to occur after the check if the head
    // is null since the tail may not be updated once the queue is made empty.
    if (self.tail == id) {
      return;
    }

    Tick.Info storage tick = self.values[id];
    Tick.Info storage tail = self.values[self.tail];

    tick.prev = self.tail;
    tail.next = id;
    self.tail = id;
  }

  function remove(Tick.Cache storage self, uint256 id) internal {
    Tick.Info storage tick = self.values[id];

    // Update the head if it is the tick we are removing.
    if (self.head == id) {
      self.head = tick.next;
    }

    // Update the tail if it is the tick we are removing.
    if (self.tail == id) {
      self.tail = tick.prev;
    }

    // Unlink the previously occupied tick from the next tick in the list.
    if (tick.prev != 0) {
      self.values[tick.prev].next = tick.next;
    }

    // Unlink the previously occupied tick from the next tick in the list.
    if (tick.next != 0) {
      self.values[tick.next].prev = tick.prev;
    }

    // Zero out the pointers.
    // NOTE(nomad): This fixes the bug where the current accrued weight would get erased.
    self.values[id].next = 0;
    self.values[id].prev = 0;
  }
}
