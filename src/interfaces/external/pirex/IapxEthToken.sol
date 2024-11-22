pragma solidity 0.8.13;


interface IapxEthToken {
    function redeem(uint256 shares, address receiver) external returns (uint256 assets);
}