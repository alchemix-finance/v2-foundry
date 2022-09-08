pragma solidity ^0.8.13;

interface IAlchemixHarvesterOptimism {
  function harvest(
    address alchemist,
    address sidecar,
    address yieldToken,
    uint256 minimumAmountOut,
    uint256 expectedExchange
  ) external;
}
