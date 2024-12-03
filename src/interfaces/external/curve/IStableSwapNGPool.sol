pragma solidity >= 0.8.0;

interface IStableSwapNGPool {
function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 minimumDy,
        address recipient
    ) external payable returns (uint256);
}