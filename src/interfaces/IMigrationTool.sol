pragma solidity >=0.5.0;

/// @title  IMigrationTool
/// @author Alchemix Finance
interface IMigrationTool {
    /// @notice Gets the current version.
    ///
    /// @return The version.
    function version() external view returns (string memory);

    /// @notice Migrates 'amount' from 'startingVault' to 'targetVault'.
    ///
    /// @param startingVault    The vault from which the user wants to withdraw from.
    /// @param targetVault      The vault that the user wishes to create a new position in.
    /// @param amount           The amount of tokens to migrate.
    /// @param maxSlippage      The maximum amount of slippage that the user will accept.
    ///
    /// @return underlyingValue The underlying Value of the new position.
    function migrateVaults(
        address startingVault,
        address targetVault,
        uint256 amount,
        uint256 maxSlippage
    ) external returns(uint256 underlyingValue);
}