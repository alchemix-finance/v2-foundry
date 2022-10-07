pragma solidity ^0.8.11;

interface IRewardDistributor {
  function claim() external returns (uint256);
}
