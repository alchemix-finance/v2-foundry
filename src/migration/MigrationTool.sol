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
import {TokenUtils} from "../libraries/TokenUtils.sol";

import {IAlToken} from "../interfaces/IAlToken.sol";
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

    mapping(address => uint256) public decimals;

    IAlchemistV2 public immutable Alchemist;
    IAlToken public immutable AlchemicToken;
    address[] public CollateralAddresses;

    constructor(InitializationParams memory params) {
        uint size = params.collateralAddresses.length;

        Alchemist       = IAlchemistV2(params.alchemist);
        AlchemicToken   = IAlToken(Alchemist.debtToken());
        CollateralAddresses = params.collateralAddresses;

        for(uint i = 0; i < size; i++){
            decimals[CollateralAddresses[i]] = TokenUtils.expectDecimals(CollateralAddresses[i]);
        }
    }

    /// @inheritdoc IMigrationTool
    function migrateVaults(
        address startingVault,
        address targetVault,
        uint256 shares,
        uint256 minReturnShares,
        uint256 minReturnUnderlying
    ) external override returns(uint256) {
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

        // If starting and target underlying tokens are not the same then revert
        if(startingParams.underlyingToken != targetParams.underlyingToken) {
            revert IllegalArgument("Cannot swap between collateral");
        }

        // Original debt
        (int256 debt, ) = Alchemist.accounts(msg.sender);

        // Debt must be positive, otherwise this tool is not needed to withdraw and re-deposit
        if(debt <= 0){
            revert IllegalState("Debt must be positive");
        }

        // Convert shares to amount of debt tokens
        uint256 debtTokenValue = _convertToDebt(shares, startingVault, startingParams.underlyingToken);
        
        // Mint tokens to this contract and burn them in the name of the user
        AlchemicToken.mint(address(this), debtTokenValue / 2);
        SafeERC20.safeApprove(address(AlchemicToken), address(Alchemist), debtTokenValue / 2);
        Alchemist.burn(debtTokenValue / 2, msg.sender);

        // Withdraw what you can from the old position
        uint256 underlyingWithdrawn = Alchemist.withdrawUnderlyingFrom(msg.sender, startingVault, shares, address(this), minReturnUnderlying);

        // Deposit into new vault
        SafeERC20.safeApprove(targetParams.underlyingToken, address(Alchemist), underlyingWithdrawn);
        uint256 newPositionShares = Alchemist.depositUnderlying(targetVault, underlyingWithdrawn, msg.sender, minReturnShares);

        // Mint al token which will be burned to fulfill flash loan requirements
        Alchemist.mintFrom(msg.sender, (debtTokenValue / 2), address(this));
        AlchemicToken.burn(debtTokenValue / 2);

	    return (newPositionShares);
	}

    function _convertToDebt(uint256 shares, address vault, address underlyingToken) internal returns(uint256) {
        uint256 underlyingValue = shares * Alchemist.getUnderlyingTokensPerShare(vault) / 10**decimals[underlyingToken];
        return underlyingValue * 10**(18 - decimals[underlyingToken]);
    }
}