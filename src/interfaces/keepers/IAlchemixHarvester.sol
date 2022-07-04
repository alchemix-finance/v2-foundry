pragma solidity ^0.8.11;

interface IAlchemixHarvester {
  function harvest(
    address alchemist,
    address yieldToken,
    uint256 minimumAmountOut
  ) external;
}
