pragma solidity 0.8.13;


interface IPirexContract {
    function deposit(address receiver, bool isCompound) external payable returns (uint256, uint256);
}