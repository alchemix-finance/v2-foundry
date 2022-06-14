// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {
    IllegalArgument,
    IllegalState,
    Unauthorized
} from "../base/Errors.sol";

import {Multicall} from "../base/Multicall.sol";
import {Mutex} from "../base/Mutex.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

import {IAlToken} from "../interfaces/IAlToken.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2State} from "../interfaces/alchemist/IAlchemistV2State.sol";
import {ICurveMetapool} from "../interfaces/ICurveMetapool.sol";
import {IMigrationTool} from "../interfaces/IMigrationTool.sol";
import {IStableSwap3Pool} from "../interfaces/external/curve/IStableSwap3Pool.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";

struct InitializationParams {
    address alchemist;
    address curveMetapool;
    address curveThreePool;
}

contract MigrationToolUSD is IMigrationTool, Multicall {
    string public override version = "1.0.0";

    mapping(address => int128) public indexes;

    IAlchemistV2 public immutable Alchemist;
    IAlToken public immutable AlchemicToken;
    ICurveMetapool public immutable CurveMetapool;
    IStableSwap3Pool public immutable CurveThreePool;

    constructor(InitializationParams memory params) {
        Alchemist       = IAlchemistV2(params.alchemist);
        AlchemicToken   = IAlToken(Alchemist.debtToken());
        CurveMetapool   = ICurveMetapool(params.curveMetapool);
        CurveThreePool  = IStableSwap3Pool(params.curveThreePool);

        indexes[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0;
        indexes[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 1;
        indexes[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 2;
    }

    /// @inheritdoc IMigrationTool
    function migrateVaults(
        address startingVault,
        address targetVault,
        uint256 shares,
        uint256 minReturn
    ) external override payable returns(uint256, uint256) {
        IAlchemistV2State.YieldTokenParams memory startingParams = Alchemist.getYieldTokenParameters(startingVault);
        IAlchemistV2State.YieldTokenParams memory targetParams = Alchemist.getYieldTokenParameters(targetVault);

        // If either vault is invalid, revert
        if(!Alchemist.isSupportedYieldToken(startingVault)) {
            revert IllegalArgument("Vault is not supported");
        }

        if(!Alchemist.isSupportedYieldToken(targetVault)) {
            revert IllegalArgument("Vault is not supported");
        }

        (int256 debt, ) = Alchemist.accounts(msg.sender);

        // Debt must be positive, otherwise this tool is not needed to withdraw and re-deposit
        if(debt <= 0){
            revert IllegalState("Debt must be positive");
        }

        AlchemicToken.mint(address(this), shares / 2);

        SafeERC20.safeApprove(Alchemist.debtToken(), address(CurveMetapool), shares / 2);
        // TODO change the second param to be a enum
        uint256 exchanged = CurveMetapool.exchange_underlying(0, indexes[startingParams.underlyingToken] + 1, shares / 2, 0);

        // Repay with underlying received from exchange
        SafeERC20.safeApprove(startingParams.underlyingToken, address(Alchemist), exchanged);
        Alchemist.repay(startingParams.underlyingToken, exchanged, msg.sender);

        // Withdraw what you can from the old position
        // TODO figure out how to withdraw as much as possible
        uint256 underlyingReturned = Alchemist.withdrawUnderlyingFrom(msg.sender, startingVault, shares * 9950 / 10000, address(this), 0);

        // If starting and target underlying tokens are not the same then make 3pool swap
        // TODO make enum
        // TODO update minimums
        if(startingParams.underlyingToken != targetParams.underlyingToken) {
            SafeERC20.safeApprove(startingParams.underlyingToken, address(CurveThreePool), underlyingReturned);
            CurveThreePool.exchange(indexes[startingParams.underlyingToken], indexes[targetParams.underlyingToken], underlyingReturned, 0);
            underlyingReturned = IERC20(targetParams.underlyingToken).balanceOf(address(this));
        }

        // Deposit into new vault
        SafeERC20.safeApprove(targetParams.underlyingToken, address(Alchemist), underlyingReturned);
        uint256 sharesReturned = Alchemist.depositUnderlying(targetVault, underlyingReturned, msg.sender, 0);

        // mint al token which will be burned to fulfill flash loan requirements
        Alchemist.mint(sharesReturned/2, address(this));
        AlchemicToken.burn(sharesReturned/2);

        uint256 userPayment = shares/2 - sharesReturned/2;

        // TODO get payment from user
        // Possibly accept underlying overpaid enough to swap for al token then refund extra
        // Less likely make user get alusd themselves

		return (sharesReturned, userPayment);
	}
}