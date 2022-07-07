// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

interface IATokenGateway {
    /// @dev Returns the address of the whitelist used by the IATokenGateway
    ///
    /// @return The address of the whitelist.
    function whitelist() external returns (address);

    /// @dev Returns the address of the alchemist used by the IATokenGateway
    ///
    /// @return The address of the alchemist.
    function alchemist() external returns (address);

    /// @dev Wraps aTokens in a StaticAToken wrapper a deposits the resulting tokens into the Alchemist.
    ///
    /// @param yieldToken       The address of the static aToken wrapper.
    /// @param amount           The amount of aTokens to wrap.
    /// @param recipient        The account in the `alchemist` that will recieve the resulting static aTokens. 
    /// @return sharesIssued    The amount of shares issued in the `alchemist` to the account owned by `recipient`.
    function deposit(address yieldToken, uint256 amount, address recipient) external returns (uint256 sharesIssued);

    /// @dev Withdraws StaticATokens from the Alchemist and unwraps them into aTokens.
    ///
    /// @param yieldToken       The address of the static aToken wrapper.
    /// @param shares           The amount of shares to withdraw from the `alchemist`.
    /// @param recipient        The account that will receive the resulting aTokens. 
    /// @return amountWithdrawn The amount of aTokens withdrawn to `recipient`.
    function withdraw(address yieldToken, uint256 shares, address recipient) external returns (uint256 amountWithdrawn);
}