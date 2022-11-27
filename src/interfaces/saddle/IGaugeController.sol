pragma solidity ^0.8.11;

interface IGaugeController {
  function vote_for_gauge_weights(address _gauge_addr, uint256 _user_weight) external;

}
