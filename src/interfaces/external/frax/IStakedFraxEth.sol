pragma solidity >= 0.8.13;

interface IStakedFraxEth {
    function convertToAssets(uint256 shares) external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
}