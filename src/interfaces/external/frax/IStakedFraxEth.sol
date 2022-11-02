pragma solidity >= 0.8.13;

interface IStakedFraxEth {
    function deposit(uint256 assets, address receiver) external returns (uint256);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
}