// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

/// @title IAlToken
interface IAlToken {
  function pauseAlchemist(address _toPause, bool _state) external;
}