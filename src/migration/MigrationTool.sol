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
    address[] collateralAddresses;
}

contract MigrationTool is IMigrationTool, Multicall {
    string public override version = "1.0.0";
    uint256 FIXED_POINT_SCALAR = 1e18;

    mapping(address => uint256) public decimals;

    IAlchemistV2 public immutable alchemist;
    IAlchemicToken public immutable alchemicToken;
    address[] public CollateralAddresses;

    constructor(InitializationParams memory params) {
        uint size = params.collateralAddresses.length;

        alchemist       = IAlchemistV2(params.alchemist);
        alchemicToken   = IAlchemicToken(alchemist.debtToken());
        CollateralAddresses = params.collateralAddresses;

        for(uint i = 0; i < size; i++){
            decimals[CollateralAddresses[i]] = TokenUtils.expectDecimals(CollateralAddresses[i]);
        }
    }

    /// @inheritdoc IMigrationTool
    function migrateVaults(
        address startingYieldToken,
        address targetYieldToken,
        uint256 shares,
        uint256 minReturnShares,
        uint256 minReturnUnderlying
    ) external override returns (uint256) {
        // Yield tokens cannot be the same to prevent slippage on current position
        if (startingYieldToken == targetYieldToken) {
            revert IllegalArgument("Yield tokens cannot be the same");
        }

        // If either yield token is invalid, revert
        if (!alchemist.isSupportedYieldToken(startingYieldToken)) {
            revert IllegalArgument("Yield token is not supported");
        }

        if (!alchemist.isSupportedYieldToken(targetYieldToken)) {
            revert IllegalArgument("Yield token is not supported");
        }

        IAlchemistV2State.YieldTokenParams memory startingParams = alchemist.getYieldTokenParameters(startingYieldToken);
        IAlchemistV2State.YieldTokenParams memory targetParams = alchemist.getYieldTokenParameters(targetYieldToken);

        // If starting and target underlying tokens are not the same then revert
        if (startingParams.underlyingToken != targetParams.underlyingToken) {
            revert IllegalArgument("Cannot swap between different collaterals");
        }

        // Original debt
        (int256 debt, ) = alchemist.accounts(msg.sender);

        uint256 debtTokenValue;
        // Avoid calculations and repayments if user doesn't need this to migrate
        if (debt > 0) {
            // Convert shares to amount of debt tokens
            debtTokenValue = _convertToDebt(shares, startingYieldToken, startingParams.underlyingToken);
            
            // Mint tokens to this contract and burn them in the name of the user
            alchemicToken.mint(address(this), debtTokenValue * FIXED_POINT_SCALAR / alchemist.minimumCollateralization());
            TokenUtils.safeApprove(address(alchemicToken), address(alchemist), debtTokenValue * FIXED_POINT_SCALAR / alchemist.minimumCollateralization());
            alchemist.burn(debtTokenValue * FIXED_POINT_SCALAR / alchemist.minimumCollateralization(), msg.sender);
        }

        // Withdraw what you can from the old position
        uint256 underlyingWithdrawn = alchemist.withdrawUnderlyingFrom(msg.sender, startingYieldToken, shares, address(this), minReturnUnderlying);

        // Deposit into new position
        TokenUtils.safeApprove(targetParams.underlyingToken, address(alchemist), underlyingWithdrawn);
        uint256 newPositionShares = alchemist.depositUnderlying(targetYieldToken, underlyingWithdrawn, msg.sender, minReturnShares);

        if (debt > 0) {
            // Mint al token which will be burned to fulfill flash loan requirements
            alchemist.mintFrom(msg.sender, (debtTokenValue * FIXED_POINT_SCALAR / alchemist.minimumCollateralization()), address(this));
            alchemicToken.burn(debtTokenValue * FIXED_POINT_SCALAR / alchemist.minimumCollateralization());
        }

	    return newPositionShares;
	}

    function _convertToDebt(uint256 shares, address yieldToken, address underlyingToken) internal returns(uint256) {
        // Math safety
        if (TokenUtils.expectDecimals(underlyingToken) > 18) {
            revert IllegalState("Underlying token decimals exceeds 18");
        }

        uint256 underlyingValue = shares * alchemist.getUnderlyingTokensPerShare(yieldToken) / 10**TokenUtils.expectDecimals(yieldToken);
        return underlyingValue * 10**(18 - decimals[underlyingToken]);
    }
}