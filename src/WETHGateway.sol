pragma solidity ^0.8.13;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./base/ErrorMessages.sol";
import "./interfaces/IAlchemistV2.sol";
import "./interfaces/external/IWETH9.sol";
import "./interfaces/IWETHGateway.sol";
import "./interfaces/IWhitelist.sol";

/// @title  WETHGateway
/// @author Alchemix Finance
contract WETHGateway is IWETHGateway, Ownable {
    /// @notice The version.
    string public constant version = "2.1.0";

    /// @notice The wrapped ethereum contract.
    IWETH9 public immutable WETH;

    /// @notice The address of the whitelist contract.
    address public whitelist;

    constructor(address weth, address _whitelist) {
        WETH = IWETH9(weth);
        whitelist = _whitelist;
    }

    /// @dev Allows for payments from the WETH contract.
    receive() external payable {
        if (IWETH9(msg.sender) != WETH) {
            revert Unauthorized("msg.sender is not WETH contract");
        }
    }

    /// @inheritdoc IWETHGateway
    function refreshAllowance(address alchemist) external onlyOwner {
        WETH.approve(alchemist, type(uint256).max);
    }

    /// @inheritdoc IWETHGateway
    function depositUnderlying(
        address alchemist,
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) external payable {
        _onlyWhitelisted();
        if (amount != msg.value) {
            revert IllegalArgument("Invalid deposit amount");
        }
        WETH.deposit{value: msg.value}();
        IAlchemistV2(alchemist).depositUnderlying(yieldToken, amount, recipient, minimumAmountOut);
    }

    /// @inheritdoc IWETHGateway
    function withdrawUnderlying(
        address alchemist,
        address yieldToken,
        uint256 shares,
        address recipient,
        uint256 minimumAmountOut
    ) external {
        _onlyWhitelisted();
        // Ensure that the underlying of the target yield token is in fact WETH
        IAlchemistV2.YieldTokenParams memory params = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken);
        if (params.underlyingToken != address(WETH)) {
            revert IllegalArgument("Token is not WETH contract");
        }

        IAlchemistV2(alchemist).withdrawUnderlyingFrom(msg.sender, yieldToken, shares, address(this), minimumAmountOut);

        uint256 amount = WETH.balanceOf(address(this));
        WETH.withdraw(amount);

        (bool success, ) = recipient.call{value: amount}(new bytes(0));
        if (!success) {
            revert IllegalState("Unsuccessful withdrawal");
        }
    }

    /// @dev Checks the whitelist for msg.sender.
    ///
    /// Reverts if msg.sender is not in the whitelist.
    function _onlyWhitelisted() internal view {
        // Check if the message sender is an EOA. In the future, this potentially may break. It is important that functions
        // which rely on the whitelist not be explicitly vulnerable in the situation where this no longer holds true.
        if (tx.origin == msg.sender) {
            return;
        }

        // Only check the whitelist for calls from contracts.
        if (!IWhitelist(whitelist).isWhitelisted(msg.sender)) {
            revert Unauthorized("Not whitelisted");
        }
    }
}