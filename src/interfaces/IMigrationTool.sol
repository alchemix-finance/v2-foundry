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
    /// @param startingYieldToken   The vault from which the user wants to withdraw from.
    /// @param targetYieldToken     The vault that the user wishes to create a new position in.
    /// @param shares               The shares of tokens to migrate.
    /// @param minReturnShares      The maximum shares of slippage that the user will accept on new position.
    /// @param minReturnUnderlying  The minimum underlying value when withdrawing from old position.
    ///
    /// @return finalShares The underlying Value of the new position.
    function migrateVaults(
        address startingYieldToken,
        address targetYieldToken,
        uint256 shares,
        uint256 minReturnShares,
        uint256 minReturnUnderlying
    ) external returns (uint256 finalShares);
}