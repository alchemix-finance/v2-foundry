pragma solidity ^0.8.11;

interface IRewardDistributor {
  function claim() external returns (uint256);

  function vote_for_gauge_weights(address gaugeAddress, uint256 weight) external;
}
