// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IConvexFraxFarm {
    function withdrawLocked(bytes32 kek_id, address destination_address)  external returns (uint256);
    function stakeLocked(uint256 liquidity, uint256 secs) external returns (bytes32);
    function earned(address account) external view returns (uint256[] memory);
    function getReward(address destination_address) external returns (uint256[] memory);
    function combinedWeightOf(address account) external view returns (uint256);
    function lockedLiquidityOf(address account) external view returns (uint256);
}