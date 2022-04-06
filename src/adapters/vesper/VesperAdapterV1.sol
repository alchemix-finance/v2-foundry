// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {
    IllegalArgument,
    IllegalState,
    Unauthorized,
    UnsupportedOperation
} from "../../base/Errors.sol";

import {Mutex} from "../../base/Mutex.sol";

import {SafeERC20} from "../../libraries/SafeERC20.sol";

import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";
import {IVesperPool} from "../../interfaces/external/vesper/IVesperPool.sol";

struct InitializationParams {
    address alchemist;
    address token;
    address underlyingToken;
}

contract VesperAdapterV1 is ITokenAdapter, Mutex {
    // using RocketPool for IRocketStorage;

    string public override version = "1.0.0";

    address public immutable alchemist;
    address public immutable override token;
    address public immutable override underlyingToken;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        token           = params.token;
        underlyingToken = params.underlyingToken;
    }

    /// @dev Checks that the message sender is the alchemist that the adapter is bound to.
    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert Unauthorized("Not alchemist");
        }
        _;
    }

    receive() external payable {
        if (msg.sender != underlyingToken && msg.sender != token) {
            revert Unauthorized("Payments only permitted from WETH or vETH");
        }
    }

    /// @inheritdoc ITokenAdapter
    function price() external view returns (uint256) {
        return IVesperPool(token).getPricePerShare();
    }

    /// @inheritdoc ITokenAdapter
    function wrap(
        uint256 amount,
        address recipient
    ) external onlyAlchemist returns (uint256) {
        // Transfer the underlying tokens from the message sender.
        SafeERC20.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        SafeERC20.safeApprove(underlyingToken, token, 1e18);

        IVesperPool(token).deposit(amount);

        // Vesper deposit does not accept a recipient argument and does not return mint amount
        // We must transfer to recipient after and use IERC20.balanceOf() for amount
        SafeERC20.safeTransfer(token, recipient, IERC20(token).balanceOf(address(this)));

        return IERC20(token).balanceOf(recipient);
    }

    // @inheritdoc ITokenAdapter
    function unwrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the tokens from the message sender.
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));

        IVesperPool(token).withdraw(amount);

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        // If the vault did not burn all of the shares then revert. This is critical in mathematical operations
        // performed by the system because the system always expects that all of the tokens were unwrapped.
        // This sometimes does not happen in cases where strategies cannot withdraw all of the requested tokens (an
        // example strategy where this can occur is with Compound and AAVE where funds may not be accessible because
        // they were lent out).
        if (balanceBefore - balanceAfter != amount) {
            revert IllegalState("Not all shares burned");
        }

        // Vesper deposit does not accept a recipient argument and does not return withdrawn amount
        // We must transfer to recipient after and use IERC20.balanceOf() for amount
        SafeERC20.safeTransfer(underlyingToken, recipient, IERC20(underlyingToken).balanceOf(address(this)));

        return IERC20(underlyingToken).balanceOf(recipient);
    }
}