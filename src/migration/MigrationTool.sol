// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

//TODO remove later
import {console} from "forge-std/console.sol";

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

contract MigrationTool is IMigrationTool, Multicall {
    string public override version = "1.0.0";

    mapping(address => uint256) public decimals;

    IAlchemistV2 public immutable Alchemist;
    IAlToken public immutable AlchemicToken;
    IStableSwap3Pool public immutable CurveThreePool;

    constructor(InitializationParams memory params) {
        Alchemist       = IAlchemistV2(params.alchemist);
        AlchemicToken   = IAlToken(Alchemist.debtToken());
        CurveThreePool  = IStableSwap3Pool(params.curveThreePool);

        // Addresses for underlying tokens if user swaps between collateral   
        decimals[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 18; // DAI     
        decimals[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 6; // USDC
        decimals[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 6; // USDT
        decimals[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 18; // WETH
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