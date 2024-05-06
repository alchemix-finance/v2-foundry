// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IConvexFraxVault {
    function stakeLockedCurveLp(uint256 liquidity, uint256 secs) external returns (bytes32 kekId);
    function stakeLocked(uint256 liquidity, uint256 secs) external returns (bytes32 kekId);
    function withdrawLockedAndUnwrap(bytes32 kekId) external;
    function getReward() external;
    function earned() external view returns (address[] memory tokenAddresses, uint256[] memory totalEarned);
}