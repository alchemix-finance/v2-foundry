// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.11;

import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {FixedPointMath} from "../FixedPointMath.sol";
import {Pool} from "./Pool.sol";

/// @title Stake
///
/// @dev A library which provides the Stake data struct and associated functions.
library Stake {
  using FixedPointMath for FixedPointMath.Number;
  using Pool for Pool.Data;
  using Stake for Stake.Data;

  struct Data {
    uint256 totalDeposited;
    uint256 totalUnclaimed;
    FixedPointMath.Number lastAccumulatedWeight;
  }

  function update(Data storage _self, Pool.Data storage _pool, Pool.Context storage _ctx) internal {
    _self.totalUnclaimed = _self.getUpdatedTotalUnclaimed(_pool, _ctx);
    _self.lastAccumulatedWeight = _pool.getUpdatedAccumulatedRewardWeight(_ctx);
  }

  function getUpdatedTotalUnclaimed(Data storage _self, Pool.Data storage _pool, Pool.Context storage _ctx)
    internal view
    returns (uint256)
  {
    FixedPointMath.Number memory _currentAccumulatedWeight = _pool.getUpdatedAccumulatedRewardWeight(_ctx);
    FixedPointMath.Number memory _lastAccumulatedWeight = _self.lastAccumulatedWeight;

    if (_currentAccumulatedWeight.cmp(_lastAccumulatedWeight) == 0) {
      return _self.totalUnclaimed;
    }

    uint256 _distributedAmount = _currentAccumulatedWeight
      .sub(_lastAccumulatedWeight)
      .mul(_self.totalDeposited)
      .truncate();

    return _self.totalUnclaimed + _distributedAmount;
  }
}