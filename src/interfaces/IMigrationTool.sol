pragma solidity >=0.5.0;

/// @title  IMigrationTool
/// @author Alchemix Finance
interface IMigrationTool {
    /// @notice Gets the current version.
    ///
    /// @return The version.
    function version() external view returns (string memory);

    /// @notice Migrates 'shares' from 'startingVault' to 'targetVault'.
    ///
    /// @param startingVault    The vault from which the user wants to withdraw from.
    /// @param targetVault      The vault that the user wishes to create a new position in.
    /// @param underlyingToken  The underlying token to withdraw and re-deposit.
    /// @param shares           The shares of tokens to migrate.
    /// @param maxSlippage      The maximum shares of slippage that the user will accept.
    ///
    /// @return finalShares The underlying Value of the new position.
    /// @return userPayment     The amount the user paid for the migration
    function migrateVaults(
        address startingVault,
        address targetVault,
        address underlyingToken,
        uint256 shares,
        uint256 maxSlippage
    ) external payable returns(uint256 finalShares, uint256 userPayment);
}