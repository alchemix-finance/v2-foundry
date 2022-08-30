pragma solidity ^0.8.13;

interface ISidecar {
    /// @notice Gets the current version.
    ///
    /// @return The version.
    function version() external view returns (string memory);

    /// @notice Gets the current reward token.
    ///
    /// @return The reward token.
    function rewardToken() external view returns (address);

    /// @notice Gets the current reward token.
    ///
    /// @return The reward token.
    function swapRouter() external view returns (address);

    function claimAndDistributeRewards(address[] calldata tokens) external returns (uint256);
}