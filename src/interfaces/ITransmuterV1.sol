// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.11;

interface ITransmuterV1  {
  function distribute (address origin, uint256 amount) external;
}