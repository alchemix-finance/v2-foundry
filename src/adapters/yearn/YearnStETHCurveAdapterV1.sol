// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IllegalArgument, IllegalState, Unauthorized} from "../../base/Errors.sol";
import {Mutex} from "../../base/Mutex.sol";

import {SafeERC20} from "../../libraries/SafeERC20.sol";

import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";
import {IStableSwap2Pool, N_COINS} from "../../interfaces/external/curve/IStableSwap2Pool.sol";
import {IYearnVaultV2} from "../../interfaces/external/yearn/IYearnVaultV2.sol";

struct InitializationParams {
    address alchemist;
    address token;
    address underlyingToken;
    address curvePool;
    address curvePoolToken;
    uint256 ethPoolIndex;
    uint256 stEthPoolIndex;
}

contract YearnStETHCurveAdapterV1 is ITokenAdapter, Mutex {
    uint256 private constant CURVE_PRECISION = 1e18;

    string public override version = "1.0.0";

    address public immutable alchemist;
    address public immutable override token;
    address public immutable override underlyingToken;
    address public immutable curvePool;
    address public immutable curvePoolToken;
    uint256 public immutable ethPoolIndex;
    uint256 public immutable stEthPoolIndex;

    constructor(InitializationParams memory params) {
        alchemist        = params.alchemist;
        token            = params.token;
        underlyingToken  = params.underlyingToken;
        curvePool        = params.curvePool;
        curvePoolToken   = params.curvePoolToken;
        ethPoolIndex     = params.ethPoolIndex;
        stEthPoolIndex   = params.stEthPoolIndex;

        // Verify and make sure that the provided ETH matches the yearn pool ETH.
        if (
            IStableSwap2Pool(params.curvePool).coins(params.ethPoolIndex) !=
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        ) {
            revert IllegalArgument("Curve pool ETH token mismatch");
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
        uint256 poolTokensPerShare = IYearnVaultV2(token).pricePerShare();
        uint256 assetsPerPoolToken = IStableSwap2Pool(curvePool).get_virtual_price();

        return poolTokensPerShare * assetsPerPoolToken / CURVE_PRECISION;
    }

    /// @inheritdoc ITokenAdapter
    function wrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the tokens from the message sender.
        SafeERC20.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        // Unwrap the WETH into ETH.
        IWETH9(underlyingToken).withdraw(amount);

        // Single side deposit the ETH into the curve pool.
        uint256[N_COINS] memory amounts;
        amounts[ethPoolIndex] = amount;

        uint256 mintedPoolTokens = IStableSwap2Pool(curvePool).add_liquidity{value: amount}(
            amounts, // Still have to specify the amounts even though we send ETH.
            0        // Slippage is handled upstream.
        );

        // Approve the vault to transfer the tokens.
        SafeERC20.safeApprove(curvePoolToken, token, mintedPoolTokens);

        // Deposit the curve pool tokens into yearn.
        return IYearnVaultV2(token).deposit(mintedPoolTokens, recipient);
    }

    // @inheritdoc ITokenAdapter
    function unwrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the tokens from the message sender.
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);

        // Withdraw the pool tokens from yearn.
        uint256 withdrawnPoolTokens = IYearnVaultV2(token).withdraw(amount, address(this), 0);

        // Single sided withdraw ETH from the pool.
        uint256 received = IStableSwap2Pool(curvePool).remove_liquidity_one_coin(
            withdrawnPoolTokens,
            int128(uint128(ethPoolIndex)),
            0
        );

        // Wrap the ETH that we received from the exchange.
        IWETH9(underlyingToken).deposit{value: received}();

        // Transfer the tokens to the recipient.
        SafeERC20.safeTransfer(underlyingToken, recipient, received);

        return received;
    }
}