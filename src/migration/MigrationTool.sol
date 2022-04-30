// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/ERC20.sol";

import {
    IllegalArgument,
    IllegalState,
    Unauthorized,
    UnsupportedOperation
} from "../base/Errors.sol";

import {Multicall} from "../base/Multicall.sol";
import {Mutex} from "../base/Mutex.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

import {IAlToken} from "../interfaces/IAlToken.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {ICurveMetapool} from "../interfaces/ICurveMetapool.sol";
import {IMigrationTool} from "../interfaces/IMigrationTool.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";

struct InitializationParams {
    address alchemist;
    address curvePool;
}

contract MigrationTool is IMigrationTool, Multicall {
    string public override version = "1.0.0";

    IAlchemistV2 public immutable Alchemist;
    IAlToken public immutable AlchemicToken;
    ICurveMetapool public immutable CurvePool;

    constructor(InitializationParams memory params) {
        Alchemist       = IAlchemistV2(params.alchemist);
        AlchemicToken   = IAlToken(Alchemist.debtToken());
        CurvePool       = ICurveMetapool(params.curvePool);
    }

    /// @inheritdoc IMigrationTool
    function migrateVaults(
        address startingVault,
        address targetVault,
        //TODO add starting and target underlying
        address underlyingToken,
        uint256 shares,
        uint256 minReturn
    ) external override payable returns(uint256, uint256) {
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

        // TODO fix this
        //AlchemicToken.mint(address(this), shares / 2);

        SafeERC20.safeApprove(Alchemist.debtToken(), address(CurvePool), shares / 2);
        // TODO change the second param to be a enum
        uint256 exchanged = CurvePool.exchange_underlying(0, 1, shares / 2, 0);

        // Repay with underlying received from exchange
        SafeERC20.safeApprove(underlyingToken, address(Alchemist), exchanged);
        Alchemist.repay(underlyingToken, exchanged, msg.sender);

        // Withdraw what you can from the old position
        // TODO figure out how to withdraw as much as possible
        uint256 underlyingReturned = Alchemist.withdrawUnderlyingFrom(msg.sender, startingVault, shares * 9950 / 10000, address(this), 0);

        // Deposit into new vault
        SafeERC20.safeApprove(underlyingToken, address(Alchemist), underlyingReturned);
        uint256 sharesReturned = Alchemist.depositUnderlying(targetVault, underlyingReturned, address(this), 0);

        // mint al token which will be burned to fulfill flash loan requirements
        Alchemist.mint(sharesReturned/2, address(this));

        // Same problem as the AlchemicToken.mint()
        // AlchemicToken.burn(sharesReturned/2);

        uint256 userPayment = (shares/2) - sharesReturned/2;

        // TODO get payment from user
        // Possibly accept underlying overpaid enough to swap for al token then refund extra
        // Less likely make user get alusd themselves

		return (sharesReturned, userPayment);
	}
}