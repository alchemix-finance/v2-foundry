pragma solidity ^0.8.13;

interface IAlchemixHarvester {
  function harvest(
    address alchemist,
    address yieldToken
  ) external;

  function setRewardRouter(address router) external;
}
