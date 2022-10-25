pragma solidity ^0.8.11;

interface IAngleVault {
  function deposit(uint256 amount, address user, address poolManager) external;
  function withdraw(uint256 amount, address burner, address dest, address poolManager) external;
}
