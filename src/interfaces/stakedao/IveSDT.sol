pragma solidity ^0.8.11;

interface IveSDT {
  function create_lock(uint256 _value, uint256 _unlock_time) external;

  function increase_amount(uint256 _value) external;

  function increase_unlock_time(uint256 _unlock_time) external;
}
