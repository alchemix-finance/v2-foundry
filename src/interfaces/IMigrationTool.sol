pragma solidity >=0.5.0;

/// @title  IMigrationTool
/// @author Alchemix Finance
interface IMigrationTool {
    event Received(address, uint);

    /// @notice Gets the current version.
    ///
    /// @return The version.
    function version() external view returns (string memory);

    /// @notice Migrates 'shares' from 'startingVault' to 'targetVault'.
    ///
    /// @param startingYieldToken   The yield token from which the user wants to withdraw.
    /// @param targetYieldToken     The yield token that the user wishes to create a new position in.
    /// @param shares               The shares of tokens to migrate.
    ///
    /// @return finalShares The underlying Value of the new position.
    function migrateVaults(
        address startingYieldToken,
        address targetYieldToken,
        uint256 shares
    ) external returns (uint256 finalShares);
}