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

import {SafeERC20} from "../libraries/SafeERC20.sol";

import {IAlToken} from "../interfaces/IAlToken.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2State} from "../interfaces/alchemist/IAlchemistV2State.sol";
import {IMigrationTool} from "../interfaces/IMigrationTool.sol";
import {IStableSwap3Pool} from "../interfaces/external/curve/IStableSwap3Pool.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";

struct InitializationParams {
    address alchemist;
    address curveMetapool;
    address curveThreePool;
}

struct UnderlyingToken {
    int128 index;
    uint256 decimals;
}

contract MigrationTool is IMigrationTool, Multicall {
    string public override version = "1.0.0";

    mapping(address => UnderlyingToken) public underlyingTokens;

    IAlchemistV2 public immutable Alchemist;
    IAlToken public immutable AlchemicToken;
    IStableSwap3Pool public immutable CurveThreePool;

    constructor(InitializationParams memory params) {
        Alchemist       = IAlchemistV2(params.alchemist);
        AlchemicToken   = IAlToken(Alchemist.debtToken());
        CurveThreePool  = IStableSwap3Pool(params.curveThreePool);

        // Addresses for underlying tokens if user swaps between collateral
        // Only for stable coins
        underlyingTokens[0x6B175474E89094C44Da98b954EedeAC495271d0F] = UnderlyingToken(0, 18);
        underlyingTokens[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = UnderlyingToken(1, 6);
        underlyingTokens[0xdAC17F958D2ee523a2206206994597C13D831ec7] = UnderlyingToken(2, 6);
        underlyingTokens[0xa258C4606Ca8206D8aA700cE2143D7db854D168c] = UnderlyingToken(3, 18);
    }

    /// @inheritdoc IMigrationTool
    function migrateVaults(
        address startingVault,
        address targetVault,
        uint256 shares,
        uint256 minReturn
    ) external override payable returns(uint256) {
        // If either vault is invalid, revert
        if(!Alchemist.isSupportedYieldToken(startingVault)) {
            revert IllegalArgument("Vault is not supported");
        }

        if(!Alchemist.isSupportedYieldToken(targetVault)) {
            revert IllegalArgument("Vault is not supported");
        }

        // Vaults cannot be the same due prevent slippage on current position
        if(startingVault == targetVault) {
            revert IllegalArgument("Vaults cannot be the same");
        }

        IAlchemistV2State.YieldTokenParams memory startingParams = Alchemist.getYieldTokenParameters(startingVault);
        IAlchemistV2State.YieldTokenParams memory targetParams = Alchemist.getYieldTokenParameters(targetVault);

        // Conversion from shares
        uint256 debtTokenValue = (shares * Alchemist.getUnderlyingTokensPerShare(startingVault) / 10**underlyingTokens[startingParams.underlyingToken].decimals) * 10**(18 - underlyingTokens[startingParams.underlyingToken].decimals);

        (int256 debt, ) = Alchemist.accounts(msg.sender);

        // Debt must be positive, otherwise this tool is not needed to withdraw and re-deposit
        if(debt <= 0){
            revert IllegalState("Debt must be positive");
        }

        AlchemicToken.mint(address(this), debtTokenValue / 2);
        SafeERC20.safeApprove(address(AlchemicToken), address(Alchemist), debtTokenValue / 2);
        Alchemist.burn(debtTokenValue / 2, msg.sender);

        // Withdraw what you can from the old position
        // TODO figure out how to withdraw as much as possible
        // TODO find better variable names
        uint256 underlyingReturned = Alchemist.withdrawUnderlyingFrom(msg.sender, startingVault, debtTokenValue * 9700 / 10000, address(this), minReturn);

        // If starting and target underlying tokens are not the same then make 3pool swap
        if(startingParams.underlyingToken != targetParams.underlyingToken) {
            SafeERC20.safeApprove(startingParams.underlyingToken, address(CurveThreePool), underlyingReturned);
            CurveThreePool.exchange(underlyingTokens[startingParams.underlyingToken].index, underlyingTokens[targetParams.underlyingToken].index, underlyingReturned, minReturn);
            underlyingReturned = IERC20(targetParams.underlyingToken).balanceOf(address(this));
        }

        // Deposit into new vault
        SafeERC20.safeApprove(targetParams.underlyingToken, address(Alchemist), underlyingReturned);
        uint256 sharesReturned = Alchemist.depositUnderlying(targetVault, underlyingReturned, msg.sender, minReturn);
        uint256 underlyingValueReturned = (sharesReturned * Alchemist.getUnderlyingTokensPerShare(startingVault) / 10**underlyingTokens[targetParams.underlyingToken].decimals) * 10**(18 - underlyingTokens[targetParams.underlyingToken].decimals);

        // Mint al token which will be burned to fulfill flash loan requirements
        Alchemist.mintFrom(msg.sender, (sharesReturned/2), address(this));
        AlchemicToken.burn(sharesReturned/2);

		return sharesReturned;
	}

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}