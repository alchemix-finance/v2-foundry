pragma solidity ^0.8.11;

interface ISanVault {
  function balanceOf(address account) external returns (uint256);
  function deposit(address _staker, uint256 _amount, bool _earn) external;
  function withdraw(uint256 _shares) external;
}
