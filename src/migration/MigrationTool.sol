// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {
    IllegalArgument,
    IllegalState,
    Unauthorized,
    UnsupportedOperation
} from "../base/Errors.sol";

import {Multicall} from "../base/Multicall.sol";
import {Mutex} from "../base/Mutex.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IMigrationTool} from "../interfaces/IMigrationTool.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";

struct InitializationParams {
    address alchemist;
}

contract MigrationTool is IMigrationTool, Multicall, Mutex {
    string public override version = "1.0.0";

    address public immutable alchemist;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
    }

    /// @inheritdoc IMigrationTool
    function migrateVaults(
        address startingVault,
        address targetVault,
        uint256 amount,
        uint256 minReturn
    ) external override returns(uint256) {
		_isVaultSupported(startingVault);
		_isVaultSupported(targetVault);
		
        // TODO Possibly change _accountExists to return so this call isnt made twice
		(int256 debt, address[] memory tokens) = IAlchemistV2(alchemist).accounts(msg.sender);

        // TODO Possibly create on alchemist variable instead of calling interface multiple times
		(uint256 shares, uint256 lastAccruedWeight) = IAlchemistV2(alchemist).positions(msg.sender, startingVault);

		// At this point not too sure how to find exact amount of underlying tokens needed
		// Using positions now lasAccruedWeight

		// Mint al tokens

		// use al tokens to withdraw

		// create new position with remainder.

        // burn tokens equal to the amount minted or revert

        //TODO remove placeholder return once everything is sorted
		return 0;
	}

    /// @dev Checks that the vault is suppoerted by the alchemist
    ///
    /// @dev 'yieldToken' must be supported by the alchemist or function will revert
    function _isVaultSupported(address yieldToken) internal view {
        if(!IAlchemistV2(alchemist).isSupportedYieldToken(yieldToken)) {
            revert IllegalArgument("Vault is not supported");
        }
    }
}