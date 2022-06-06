// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.5.0;

interface ITransmuterV1 {
  function distribute(address origin, uint256 amount) external;

  function migrateFunds(address migrateTo) external;

  function setPause(bool val) external;
}