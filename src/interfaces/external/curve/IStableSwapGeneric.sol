// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IStableSwapGeneric {
    function coins(uint256 index) external view returns (address);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 minimumDy
    ) external;
}