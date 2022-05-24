// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {
    IllegalArgument,
    IllegalState,
    Unauthorized,
    UnsupportedOperation
} from "../../base/ErrorMessages.sol";

import {MutexLock} from "../../base/MutexLock.sol";

import {SafeERC20} from "../../libraries/SafeERC20.sol";

import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";
import {IVesperPool} from "../../interfaces/external/vesper/IVesperPool.sol";
import {IVesperRewards} from "../../interfaces/external/vesper/IVesperRewards.sol";

struct InitializationParams {
    address alchemist;
    address token;
    address underlyingToken;
}

contract VesperAdapterV1 is ITokenAdapter, MutexLock {

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

    /// @inheritdoc ITokenAdapter
    function price() external view returns (uint256) {
        return IVesperPool(token).pricePerShare();
    }

    /// @inheritdoc ITokenAdapter
    function wrap(
        uint256 amount,
        address recipient
    ) external onlyAlchemist returns (uint256) {
        // Transfer the underlying tokens from the message sender.
        SafeERC20.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        SafeERC20.safeApprove(underlyingToken, token, amount);

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));

        // Vesper deposit does not accept a recipient argument and does not return mint amount
        IVesperPool(token).deposit(amount);

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        uint256 minted = balanceAfter - balanceBefore;

        // We must transfer to recipient after and use IERC20.balanceOf() for amount
        SafeERC20.safeTransfer(token, recipient, minted);

        return minted;
    }

    // @inheritdoc ITokenAdapter
    function unwrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the tokens from the message sender.
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);

        uint256 balanceBeforeUnderlying = IERC20(underlyingToken).balanceOf(address(this));
        uint256 balanceBeforeYieldToken = IERC20(token).balanceOf(address(this));
        
        // Vesper withdraw does not accept a recipient argument and does not return withdrawn amount
        IVesperPool(token).withdraw(amount);

        uint256 balanceAfterUnderlying = IERC20(underlyingToken).balanceOf(address(this));
        uint256 balanceAfterYieldToken = IERC20(token).balanceOf(address(this));

        uint256 withdrawn = balanceAfterUnderlying - balanceBeforeUnderlying;

        if (balanceBeforeYieldToken - balanceAfterYieldToken != amount) {
            revert IllegalState("Not all shares were burned");
        }

        // We must transfer to recipient after and use IERC20.balanceOf() for amount
        SafeERC20.safeTransfer(underlyingToken, recipient, withdrawn);

        return withdrawn;
    }
}