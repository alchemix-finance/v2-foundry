pragma solidity >=0.5.0;

/// @title  IWETHGateway
/// @author Alchemix Finance
interface IWETHGateway {
    /// @notice Refreshes the wrapped ethereum ERC20 approval for an alchemist contract.
    ///
    /// @param alchemist The address of the alchemist to refresh the allowance for.
    function refreshAllowance(address alchemist) external;

    /// @notice Takes ethereum, converts it to wrapped ethereum, and then deposits it into an alchemist.
    ///
    /// See [IAlchemistV2Actions.depositUnderlying](./alchemist/IAlchemistV2Actions.md#depositunderlying) for more details.
    ///
    /// @param alchemist        The address of the alchemist to deposit wrapped ethereum into.
    /// @param yieldToken       The yield token to deposit the wrapped ethereum as.
    /// @param amount           The amount of ethereum to deposit.
    /// @param recipient        The address which will receive the deposited yield tokens.
    /// @param minimumAmountOut The minimum amount of yield tokens that are expected to be deposited to `recipient`.
    function depositUnderlying(
        address alchemist,
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) external payable;

    /// @notice Withdraws a wrapped ethereum based yield token from an alchemist, converts it to ethereum, and then
    ///         transfers it to the recipient.
    ///
    /// A withdraw approval on the alchemist is required for this call to succeed.
    ///
    /// See [IAlchemistV2Actions.withdrawUnderlying](./alchemist/IAlchemistV2Actions.md#withdrawunderlying) for more details.
    ///
    /// @param alchemist        The address of the alchemist to withdraw wrapped ethereum from.
    /// @param yieldToken       The address of the yield token to withdraw.
    /// @param shares           The amount of shares to withdraw.
    /// @param recipient        The address which will receive the ethereum.
    /// @param minimumAmountOut The minimum amount of underlying tokens that are expected to be withdrawn to `recipient`.
    function withdrawUnderlying(
        address alchemist,
        address yieldToken,
        uint256 shares,
        address recipient,
        uint256 minimumAmountOut
    ) external;
}