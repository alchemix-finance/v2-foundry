
// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

interface IVesperRewards {
    function claimReward(address) external;

    function claimable(address) external view returns (address[] memory, uint256[] memory);

    function rewardTokens(uint256) external view returns (address);
}