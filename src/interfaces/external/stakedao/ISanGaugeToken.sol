pragma solidity ^0.8.11;

interface ISanGaugeToken {
  function decimals() external view returns (uint256);

  function claim_rewards(address _address) external;
}
