// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {IllegalArgument, IllegalState, Unauthorized} from "../../base/Errors.sol";
import {Mutex} from "../../base/Mutex.sol";

import {SafeERC20} from "../../libraries/SafeERC20.sol";

import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";
import {IStableSwap2Pool} from "../../interfaces/external/curve/IStableSwap2Pool.sol";
import {IStETH} from "../../interfaces/external/lido/IStETH.sol";
import {IWstETH} from "../../interfaces/external/lido/IWstETH.sol";

struct InitializationParams {
    address alchemist;
    address token;
    address parentToken;
    address underlyingToken;
    address curvePool;
    uint256 stEthPoolIndex;
    uint256 ethPoolIndex;
}

contract WstETHAdapterV1 is ITokenAdapter, Mutex {
    string public override version = "1.0.0";

    address public immutable alchemist;
    address public immutable override token;
    address public immutable parentToken;
    address public immutable override underlyingToken;
    address public immutable curvePool;
    uint256 public immutable ethPoolIndex;
    uint256 public immutable stEthPoolIndex;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        token           = params.token;
        parentToken     = params.parentToken;
        underlyingToken = params.underlyingToken;
        curvePool       = params.curvePool;
        ethPoolIndex    = params.ethPoolIndex;
        stEthPoolIndex  = params.stEthPoolIndex;

        // Verify and make sure that the provided ETH matches the curve pool ETH.
        if (
            IStableSwap2Pool(params.curvePool).coins(params.ethPoolIndex) !=
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        ) {
            revert IllegalArgument("Curve pool ETH token mismatch");
        }

        // Verify and make sure that the provided stETH matches the curve pool stETH.
        if (
            IStableSwap2Pool(params.curvePool).coins(params.stEthPoolIndex) !=
            params.parentToken
        ) {
            revert IllegalArgument("Curve pool stETH token mismatch");
        }
    }

    /// @dev Checks that the message sender is the alchemist that the adapter is bound to.
    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert Unauthorized("Not alchemist");
        }
        _;
    }

    receive() external payable {
        if (msg.sender != underlyingToken && msg.sender != curvePool) {
            revert Unauthorized("Payments only permitted from WETH or curve pool");
        }
    }

    /// @inheritdoc ITokenAdapter
    function price() external view returns (uint256) {
        return IWstETH(token).getStETHByWstETH(10**SafeERC20.expectDecimals(token));
    }

    /// @inheritdoc ITokenAdapter
    function wrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the tokens from the message sender.
        SafeERC20.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        // Unwrap the WETH into ETH. We do not check if the contract properly unwrapped the
        // ethereum because it is an immutable contract and we expect that its output is reliable.
        IWETH9(underlyingToken).withdraw(amount);

        // Wrap the ETH into wstETH. We can do this by using the receive function.
        uint256 startingWstEthBalance = IERC20(token).balanceOf(address(this));

        (bool ok,) = token.call{value: amount}(new bytes(0));
        if (!ok) revert IllegalState("Failed to wrap ETH into wstETH");

        uint256 endingWstEthBalance = IERC20(token).balanceOf(address(this));

        // Transfer the minted wstETH to the recipient.
        uint256 mintedWstETh = endingWstEthBalance - startingWstEthBalance;
        SafeERC20.safeTransfer(token, recipient, mintedWstETh);

        return mintedWstETh;
    }

    // @inheritdoc ITokenAdapter
    function unwrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the tokens from the message sender.
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);

        // Unwrap the wstETH into stETH.
        uint256 startingWstEthBalance = IStETH(parentToken).balanceOf(address(this));
        IWstETH(token).unwrap(amount);
        uint256 endingWstEthBalance = IStETH(parentToken).balanceOf(address(this));

        // Approve the curve pool to transfer the tokens.
        uint256 unwrappedWstEth = endingWstEthBalance - startingWstEthBalance;
        SafeERC20.safeApprove(parentToken, curvePool, unwrappedWstEth);

        // Exchange the stETH for ETH. We do not check the curve pool because it is an immutable
        // contract and we expect that its output is reliable.
        uint256 received = IStableSwap2Pool(curvePool).exchange(
            int128(uint128(stEthPoolIndex)), // Why are we here, just to suffer?
            int128(uint128(ethPoolIndex)),   //                       (╥﹏╥)
            unwrappedWstEth,
            0                                // <- Slippage is handled upstream
        );

        // Wrap the ETH that we received from the exchange.
        IWETH9(underlyingToken).deposit{value: received}();

        // Transfer the tokens to the recipient.
        SafeERC20.safeTransfer(underlyingToken, recipient, received);

        return received;
    }
}