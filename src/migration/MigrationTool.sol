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
import {SafeCast} from "../libraries/SafeCast.sol";

struct InitializationParams {
    address alchemist;
    address[] collateralAddresses;
}

struct PreviewParams {
    IAlchemistV2State.YieldTokenParams startingParams;
    IAlchemistV2State.YieldTokenParams targetParams;
    int256 currentDebt;
    uint256 underlyingValue;
    uint256 newShares;
    uint256 debtTokenValue;
    uint256 newDebtTokenValue;
    uint256 remainingDebt;
}

contract MigrationTool is IMigrationTool, Multicall {
    string public override version = "1.0.1";
    uint256 public immutable FIXED_POINT_SCALAR = 1e18;
    uint256 public immutable BPS = 10000;

    mapping(address => uint256) public decimals;

    IAlchemistV2 public immutable alchemist;
    IAlchemicToken public immutable alchemicToken;

    address[] public collateralAddresses;

    constructor(InitializationParams memory params) {
        uint size = params.collateralAddresses.length;

        alchemist       = IAlchemistV2(params.alchemist);
        alchemicToken   = IAlchemicToken(alchemist.debtToken());
        collateralAddresses = params.collateralAddresses;

        for(uint i = 0; i < size; i++){
            decimals[collateralAddresses[i]] = TokenUtils.expectDecimals(collateralAddresses[i]);
        }
    }

    /// @inheritdoc IMigrationTool
    function previewMigration(      
        address account,
        address startingYieldToken,
        address targetYieldToken,
        uint256 shares
    ) external view returns (bool, string memory, uint256, uint256, uint256) {
        PreviewParams memory params;

        params.startingParams = alchemist.getYieldTokenParameters(startingYieldToken);
        params.targetParams = alchemist.getYieldTokenParameters(targetYieldToken);

        // Calculate the amount of shares a user will receive in the new vault and the debt token value of both positions
        params.underlyingValue = shares * alchemist.getUnderlyingTokensPerShare(startingYieldToken) / 10**TokenUtils.expectDecimals(startingYieldToken);
        params.newShares = params.underlyingValue * 10**TokenUtils.expectDecimals(targetYieldToken) / alchemist.getUnderlyingTokensPerShare(targetYieldToken);
        params.debtTokenValue = _convertToDebt(shares, startingYieldToken, params.startingParams.underlyingToken);
        params.newDebtTokenValue = _convertToDebt(params.newShares, targetYieldToken, params.targetParams.underlyingToken);

        // If attempting to move more shares than then new vault can accept
        if ( params.targetParams.activeBalance + params.newShares  > params.targetParams.maximumExpectedValue) {
            return (
                false, 
                "Migrated amount exceeds new vault capacity! Reduce migration amount.", 
                params.targetParams.activeBalance + params.newShares - params.targetParams.maximumExpectedValue,
                0,
                0
            );
        }

        // If debt new debt value is less than previous, check that the user has the ability to cover the difference
        (params.currentDebt, ) = alchemist.accounts(account);
        if (params.currentDebt > 0) {
            params.remainingDebt = (alchemist.totalValue(account) * FIXED_POINT_SCALAR / alchemist.minimumCollateralization()) - uint256(params.currentDebt);
            if (params.newDebtTokenValue < params.debtTokenValue && params.remainingDebt < params.debtTokenValue - params.newDebtTokenValue) {
                return (
                    false, 
                    "Slippage exceeded! New position exceeds mint allowance.",
                    params.debtTokenValue - params.newDebtTokenValue - params.remainingDebt,
                    0,
                    0
                );
            }
        }

        return (
            true,
            "Migration is ready!",
            0,
            params.newShares * 8500 / BPS,
            params.underlyingValue * 8500 / BPS
        );
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

        // Avoid calculations and repayments if user doesn't need this to migrate
        uint256 debtTokenValue;
        uint256 mintable;
        if (debt > 0) {
            // Convert shares to amount of debt tokens
            debtTokenValue = _convertToDebt(shares, startingYieldToken, startingParams.underlyingToken);
            mintable = debtTokenValue * FIXED_POINT_SCALAR / alchemist.minimumCollateralization();
            // Mint tokens to this contract and burn them in the name of the user
            alchemicToken.mint(address(this), mintable);
            TokenUtils.safeApprove(address(alchemicToken), address(alchemist), mintable);
            alchemist.burn(mintable, msg.sender);
        }

        // Withdraw what you can from the old position
        uint256 underlyingWithdrawn = alchemist.withdrawUnderlyingFrom(msg.sender, startingYieldToken, shares, address(this), minReturnUnderlying);

        // Deposit into new position
        TokenUtils.safeApprove(targetParams.underlyingToken, address(alchemist), underlyingWithdrawn);
        uint256 newPositionShares = alchemist.depositUnderlying(targetYieldToken, underlyingWithdrawn, msg.sender, minReturnShares);

        if (debt > 0) {
            (int256 latestDebt, ) = alchemist.accounts(msg.sender);
            // Mint al token which will be burned to fulfill flash loan requirements
            alchemist.mintFrom(msg.sender, SafeCast.toUint256(debt - latestDebt), address(this));
            alchemicToken.burn(alchemicToken.balanceOf(address(this)));
        }

	    return newPositionShares;
	}

    function _convertToDebt(uint256 shares, address yieldToken, address underlyingToken) internal view returns(uint256) {
        // Math safety
        if (TokenUtils.expectDecimals(underlyingToken) > 18) {
            revert IllegalState("Underlying token decimals exceeds 18");
        }

        uint256 underlyingValue = shares * alchemist.getUnderlyingTokensPerShare(yieldToken) / 10**TokenUtils.expectDecimals(yieldToken);
        return underlyingValue * 10**(18 - decimals[underlyingToken]);
    }
}