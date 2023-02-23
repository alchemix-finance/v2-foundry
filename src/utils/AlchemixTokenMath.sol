// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {
    IllegalArgument,
    IllegalState,
    Unauthorized
} from "../base/ErrorMessages.sol";

import {TokenUtils} from "../libraries/TokenUtils.sol";

import {IAlchemicToken} from "../interfaces/IAlchemicToken.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";

contract AlchemixTokenMath {
    string public version = "1.0.0";
    uint256 FIXED_POINT_SCALAR = 1e18;

    function normalizeSharesToDebtTokens(uint256 shares, address yieldToken, address underlyingToken, address alchemist) external view returns(uint256) {
        // Math safety
        if (TokenUtils.expectDecimals(underlyingToken) > 18) {
            revert IllegalState("Underlying token decimals exceeds 18");
        }

        uint256 underlyingValue = shares * IAlchemistV2(alchemist).getUnderlyingTokensPerShare(yieldToken) / 10**TokenUtils.expectDecimals(yieldToken);
        return underlyingValue * 10**(18 - TokenUtils.expectDecimals(underlyingToken));
    }

    function normalizeDebtTokensToShares(uint256 debt, address yieldToken, address underlyingToken, address alchemist) external view returns(uint256) {
        // Math safety
        if (TokenUtils.expectDecimals(underlyingToken) > 18) {
            revert IllegalState("Underlying token decimals exceeds 18");
        }

        uint256 underlyingValue = debt / 10**(18 - TokenUtils.expectDecimals(underlyingToken));
        return underlyingValue / IAlchemistV2(alchemist).getUnderlyingTokensPerShare(yieldToken) * 10**TokenUtils.expectDecimals(yieldToken);
    }
}