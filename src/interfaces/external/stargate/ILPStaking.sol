pragma solidity >=0.5.0;

interface ILPStaking {
    function userInfo(uint256 poolId, address user) external view returns (uint256 amount, uint256 rewardDebt);
    function pendingStargate(uint256 poolId, address user) external view returns (uint256);
    function deposit(uint256 poolId, uint256 amount) external;
}