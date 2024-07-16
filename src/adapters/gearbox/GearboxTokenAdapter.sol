pragma solidity ^0.8.11;

import { IllegalState } from "../../base/Errors.sol";

import "../../interfaces/ITokenAdapter.sol";
import { IERC4626 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "../../libraries/TokenUtils.sol";
import { IGearboxZap } from "../../interfaces/external/gearbox/IGearboxZap.sol";
// import { IFarmingPool } from "../../interfaces/external/gearbox/IFarmingPool.sol";

/// @title GearboxTokenAdapter
/// @author Alchemix Finance
contract GearboxTokenAdapter is ITokenAdapter {
    uint256 private constant MAXIMUM_SLIPPAGE = 10000;
    string public constant override version = "1.0.0";

    address public immutable override token; // Gearbox Diesel Token (Yield Token)
    address public immutable farmToken; // Gearbox Farming Pool
    address public immutable override underlyingToken; // Underlying Token (e.g., WETH)
    address public immutable zap; // Gearbox Zap

    constructor(address _token, address _farmToken, address _underlyingToken, address _zap) {
        token = _token;
        farmToken = _farmToken;
        underlyingToken = _underlyingToken;
        zap = _zap;
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        // Get the price of Diesel Token in terms of the underlying token
        return IERC4626(token).convertToAssets(1e18);
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        // Transfer underlying tokens from msg.sender to this contract
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        // Approve the Gearbox Diesel Token contract to spend the underlying tokens
        TokenUtils.safeApprove(underlyingToken, token, 0);
        TokenUtils.safeApprove(underlyingToken, token, amount);

        uint256 expectedShares = IERC4626(token).convertToShares(amount);
        // Deposit underlying tokens into the Gearbox Diesel Token contract and receive Diesel Tokens
        // TODO: Double check the recipient should be recipient or address(this)
        return IGearboxZap(zap).zapIn(amount, recipient, expectedShares);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        // Transfer Diesel Tokens from msg.sender to this contract
        TokenUtils.safeTransferFrom(farmToken, msg.sender, address(this), amount);

        uint256 expectedTokens = IERC4626(token).convertToAssets(amount);
        // Redeem Diesel Tokens for underlying tokens and send them to the recipient
        // TODO: Double check the recipient should be recipient or address(this)
        uint256 amountWithdrawn = IGearboxZap(zap).zapIn(amount, recipient, expectedTokens);

        return amountWithdrawn;
    }
}