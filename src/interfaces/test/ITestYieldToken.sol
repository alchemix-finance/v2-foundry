pragma solidity >=0.5.0;

import "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title  ITestYieldToken
/// @author Alchemix Finance
interface ITestYieldToken is IERC20 {
    /// @notice Gets the address of underlying token that the yield token wraps.
    ///
    /// @return The underlying token address.
    function underlyingToken() external view returns (address);

    /// @notice Gets the conversion rate of one whole unit of this token for the underlying token.
    ///
    /// @return The price.
    function price() external view returns (uint256);

    /// @notice Mints an amount of yield tokens from `amount` underlying tokens and transfers them to `recipient`.
    ///
    /// @param amount    The amount of underlying tokens.
    /// @param recipient The address which will receive the minted yield tokens.
    ///
    /// @return The amount of minted yield tokens.
    function mint(uint256 amount, address recipient) external returns (uint256);

    /// @notice Redeems yield tokens for underlying tokens.
    ///
    /// @param amount    The amount of yield tokens to redeem.
    /// @param recipient The address which will receive the redeemed underlying tokens.
    ///
    /// @return The amount of underlying tokens that the yield tokens were redeemed for.
    function redeem(uint256 amount, address recipient) external returns (uint256);

    /// @notice Simulates an atomic harvest of `amount` underlying tokens.
    ///
    /// @param amount The amount of the underlying token.
    function slurp(uint256 amount) external;

    /// @notice Simulates an atomic loss of `amount` underlying tokens.
    ///
    /// @param amount The amount of the underlying token.
    function siphon(uint256 amount) external;
}
