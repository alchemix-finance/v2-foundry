pragma solidity >=0.5.0;

/// @title  IMigrationTool
/// @author Alchemix Finance
interface IMigrationTool {
    event Received(address, uint);

    /// @notice Gets the current version.
    ///
    /// @return The version.
    function version() external view returns (string memory);

    /// @notice Determines if a migration will be succesful before allowing a user to migrate.
    ///
    /// @param account                  The account to migrate.
    /// @param startingYieldToken       The starting vault.
    /// @param targetYieldToken         The target vault.
    /// @param shares                   The shares to migrate.
    ///
    /// @return canMigrate              If the migration will be succesful.
    /// @return state                   The specific reason the migration will fail.
    /// @return amountToAdjust          This is the amount a user is exceeding the vault by, or how much debt value the user must cover.
    /// @return minReturnShares         Minimum shares for the migrate function.
    /// @return minReturnUnderlying     Minimum underlying for the migrate function.
    function previewMigration(      
        address account,  
        address startingYieldToken,
        address targetYieldToken,
        uint256 shares
    ) external view returns (bool canMigrate, string memory state, uint256 amountToAdjust, uint256 minReturnShares, uint256 minReturnUnderlying);

    /// @notice Migrates 'shares' from 'startingVault' to 'targetVault'.
    ///
    /// @param startingYieldToken   The yield token from which the user wants to withdraw.
    /// @param targetYieldToken     The yield token that the user wishes to create a new position in.
    /// @param shares               The shares of tokens to migrate.
    /// @param minReturnShares      The maximum shares of slippage that the user will accept on new position.
    /// @param minReturnUnderlying  The minimum underlying value when withdrawing from old position.
    ///
    /// @return finalShares         The underlying Value of the new position.
    function migrateVaults(
        address startingYieldToken,
        address targetYieldToken,
        uint256 shares,
        uint256 minReturnShares,
        uint256 minReturnUnderlying
    ) external returns (uint256 finalShares);
}