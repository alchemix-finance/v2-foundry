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

import {LibFuse} from "../../libraries/LibFuse.sol";
import {SafeERC20} from "../../libraries/SafeERC20.sol";

import {ICERC20} from "../../interfaces/external/compound/ICERC20.sol";
import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";

struct InitializationParams {
    address alchemist;
    address token;
    address underlyingToken;
}

contract FuseTokenAdapterV1 is ITokenAdapter, MutexLock {
    string public override version = "1.0.0";

    address public immutable alchemist;
    address public immutable override token;
    address public immutable override underlyingToken;

    /// @dev Fuse error code for a noop.
    uint256 private constant NO_ERROR = 0;

    /// @dev Scalar for all fixed point numbers returned by Fuse.
    uint256 private constant FIXED_POINT_SCALAR = 1e18;

    /// @notice An error used when a call to Fuse fails.
    ///
    /// @param code The error code.
    error FuseError(uint256 code);

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
        return LibFuse.viewExchangeRate(ICERC20(token));
    }

    /// @inheritdoc ITokenAdapter
    function wrap(
        uint256 amount,
        address recipient
    ) external onlyAlchemist returns (uint256) {
        SafeERC20.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        SafeERC20.safeApprove(underlyingToken, token, amount);

        uint256 startingBalance = IERC20(token).balanceOf(address(this));

        uint256 error;
        if ((error = ICERC20(token).mint(amount)) != NO_ERROR) {
            revert FuseError(error);
        }

        uint256 endingBalance = IERC20(token).balanceOf(address(this));
        uint256 mintedAmount = endingBalance - startingBalance;

        SafeERC20.safeTransfer(token, recipient, mintedAmount);

        return mintedAmount;
    }

    // @inheritdoc ITokenAdapter
    function unwrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);

        uint256 startingBalance = IERC20(underlyingToken).balanceOf(address(this));

        uint256 error;
        if ((error = ICERC20(token).redeem(amount)) != NO_ERROR) {
            revert FuseError(error);
        }

        uint256 endingBalance = IERC20(underlyingToken).balanceOf(address(this));
        uint256 redeemedAmount = endingBalance - startingBalance;

        SafeERC20.safeTransfer(underlyingToken, recipient, redeemedAmount);

        return redeemedAmount;
    }
}