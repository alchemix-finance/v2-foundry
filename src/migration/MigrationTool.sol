// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {
    IllegalArgument,
    IllegalState,
    Unauthorized
} from "../base/ErrorMessages.sol";

import {Multicall} from "../base/Multicall.sol";
import {Mutex} from "../base/Mutex.sol";

import {TokenUtils} from "../libraries/TokenUtils.sol";

import {IAlchemicToken} from "../interfaces/IAlchemicToken.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2State} from "../interfaces/alchemist/IAlchemistV2State.sol";
import {IMigrationTool} from "../interfaces/IMigrationTool.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";

struct InitializationParams {
    address alchemist;
}

contract MigrationTool is IMigrationTool, Multicall {
    string public override version = "1.0.0";

    IAlchemistV2 public immutable alchemist;
    IAlchemicToken public immutable alchemicToken;

    constructor(InitializationParams memory params) {
        alchemist       = IAlchemistV2(params.alchemist);
        alchemicToken   = IAlchemicToken(alchemist.debtToken());
    }

    /// @inheritdoc IMigrationTool
    function migrateVaults(
        address startingYieldToken,
        address targetYieldToken,
        uint256 shares,
        uint256 minReturnShares,
        uint256 minReturnUnderlying
    ) external override returns(uint256) {
        // Vaults cannot be the same due prevent slippage on current position
        if (startingYieldToken == targetYieldToken) {
            revert IllegalArgument("Vaults cannot be the same");
        }

        // If either vault is invalid, revert
        if (!alchemist.isSupportedYieldToken(startingYieldToken)) {
            revert IllegalArgument("Vault is not supported");
        }

        if (!alchemist.isSupportedYieldToken(targetYieldToken)) {
            revert IllegalArgument("Vault is not supported");
        }

        IAlchemistV2State.YieldTokenParams memory startingParams = alchemist.getYieldTokenParameters(startingYieldToken);
        IAlchemistV2State.YieldTokenParams memory targetParams = alchemist.getYieldTokenParameters(targetYieldToken);

        // If starting and target underlying tokens are not the same then revert
        if (startingParams.underlyingToken != targetParams.underlyingToken) {
            revert IllegalArgument("Cannot swap between collateral");
        }

        // Determine the amount of alchemic tokens to burn in order to free the desired amount of shares
        uint256 debtToFreeshares = _debtToFreeShares(shares, startingYieldToken, startingParams.underlyingToken);

        if (debtToFreeshares > 0) {
            // Mint tokens to this contract and burn them in the name of the user
            alchemicToken.mint(address(this), debtToFreeshares);
            TokenUtils.safeApprove(address(alchemicToken), address(alchemist), debtToFreeshares);
            alchemist.burn(debtToFreeshares, msg.sender);
        }

        // Withdraw what you can from the old position
        uint256 underlyingWithdrawn = alchemist.withdrawUnderlyingFrom(msg.sender, startingYieldToken, shares, address(this), minReturnUnderlying);

        // Deposit into new vault
        TokenUtils.safeApprove(targetParams.underlyingToken, address(alchemist), underlyingWithdrawn);
        uint256 newPositionShares = alchemist.depositUnderlying(targetYieldToken, underlyingWithdrawn, msg.sender, minReturnShares);

        if (debtToFreeshares > 0) {
            // Mint al token which will be burned to fulfill flash loan requirements
            alchemist.mintFrom(msg.sender, (debtToFreeshares), address(this));
            alchemicToken.burn(debtToFreeshares);
        }

	    return newPositionShares;
	}

    // The number of debt tokens needed to free up locked shares
    // Locked shares are the remainder of shares after all freed shares have been withdrawn
    // If a user is overcollateralized some or all shares can be freed up without minting and burning more debt tokens
    function _debtToFreeShares(uint256 shares, address vault, address startingUnderlyingToken) internal returns(uint256) {
        uint256 minimumCollateralization = alchemist.minimumCollateralization();
        (int256 debt, address[] memory depositedTokens) = alchemist.accounts(msg.sender);

        // Shares can all be freed without burning any tokens
        if (debt <= 0) {
            return 0;
        }

        // Value of every position in units of debt token
        uint256 totalAccountValue = 0;

        for (uint256 i = 0; i < depositedTokens.length; i++) {
            IAlchemistV2State.YieldTokenParams memory yieldTokenParams = alchemist.getYieldTokenParameters(depositedTokens[i]);
            // Ensure math safety
            if (yieldTokenParams.decimals > 18) {
                revert IllegalState("Underlying token decimals exceeds 18");
            }

            // Convert shares into underlying tokens and then into debt tokens
            (uint256 yieldTokenShares, ) = alchemist.positions(msg.sender, depositedTokens[i]);
            uint256 underlyingValue = yieldTokenShares * alchemist.getUnderlyingTokensPerShare(depositedTokens[i]) / 10**yieldTokenParams.decimals;
            uint256 debtTokenValue = underlyingValue * 10**(18 - TokenUtils.expectDecimals(yieldTokenParams.underlyingToken));
            totalAccountValue += debtTokenValue;
        }

        // Calculate the collateralization ratio of the total account value
        // Use the difference between this ratio and the minimum ratio (2:1) to calculate the shares that can't be freed without burning debt tokens
        // Convert the remaining shares to debt token value
        uint256 collateralization =  totalAccountValue * 1e18 / uint256(debt);
        uint256 underlyingValueOfShares = shares *  alchemist.getUnderlyingTokensPerShare(vault) / 10**TokenUtils.expectDecimals(vault);
        uint256 debtTokenValueOfShares = underlyingValueOfShares * 10**(18 - TokenUtils.expectDecimals(startingUnderlyingToken));
        uint256 lockedSharesToDebtTokens = debtTokenValueOfShares - uint256(debt) * (collateralization - minimumCollateralization);

        // The debt token value of the specified share divided by the remaining collateralization ratio
        // We can assume that the collateralization ratio of locked shares is the minimum (2:1) given that we are not counting shares that can be freed without burning
        return lockedSharesToDebtTokens * 1e18 / minimumCollateralization;
    }
}