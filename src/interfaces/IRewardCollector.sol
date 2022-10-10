pragma solidity ^0.8.13;

interface IRewardCollector {
    /// @notice Gets the current version.
    ///
    /// @return The version.
    function version() external view returns (string memory);

    /// @notice Gets the current reward token.
    ///
    /// @return The reward token.
    function rewardToken() external view returns (address);

    /// @notice Gets the current swap router.
    ///
    /// @return The swap router address.
    function swapRouter() external view returns (address);

    /// @notice Gets the current debt token.
    ///
    /// @return The debt token
    function debtToken() external view returns (address);

    /// @notice Claims rewards tokens, swaps for alUSD.
    ///
    /// @param  tokens          The yield tokens to claim rewards for.
    /// @param  minimumSwap     The minimum returns to accept.
    ///
    /// @return claimed         The amount of reward tokens claimed.
    function claimAndDistributeRewards(address[] calldata tokens, uint256 minimumSwap) external returns (uint256 claimed);
}