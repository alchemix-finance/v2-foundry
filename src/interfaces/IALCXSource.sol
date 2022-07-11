// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IALCXSource {
    function getStakeTotalDeposited(address _user, uint256 _poolId) external view returns (uint256);
    function claim(uint256 _poolId) external;
    function deposit(uint256 _poolId, uint256 _depositAmount) external;
    function withdraw(uint256 _poolId, uint256 _withdrawAmount) external;
}