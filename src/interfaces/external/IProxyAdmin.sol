// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IProxyAdmin {
  function getProxyImplementation(address proxy) external view returns (address);

  function getProxyAdmin(address proxy) external view returns (address);

  function changeProxyAdmin(address proxy, address newAdmin) external;

  function upgrade(address proxy, address implementation) external;

  function upgradeAndCall(
    address proxy,
    address implementation,
    bytes memory data
  ) external;
}