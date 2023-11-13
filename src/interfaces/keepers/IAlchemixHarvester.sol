pragma solidity ^0.8.13;

interface IAlchemixHarvester {
  function harvest(
    address alchemist,
    address yieldToken
  ) external;
}
