// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.8.11;

interface IDelegateRegistry {
  function setDelegate(bytes32 id, address delegate) external;

  function clearDelegate(bytes32 id) external;
}
