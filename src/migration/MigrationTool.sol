// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {
    IllegalArgument,
    IllegalState,
    Unauthorized,
    UnsupportedOperation
} from "../../base/Errors.sol";

import {Multicall} from "../../base/Multicall.sol";
import {Mutex} from "../../base/Mutex.sol";

import {SafeERC20} from "../../libraries/SafeERC20.sol";

import {IAlchemistV2} from "../../interfaces/IAlchemistV2.sol";
import {IMigrationTool} from "../../interfaces/IMigrationTool.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";

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
        _accountExists(msg.sender);
		isVaultSupported(startingVault);
		isVaultSupported(targetVault);
		
        // TODO Possibly change _accountExists to return so this call isnt made twice
		(uint256 debt, address[] tokens) = IAlchemistV2(alchemist).accounts(msg.sender);

        // TODO Possibly create on alchemist variable instead of calling interface multiple times
		(uint256 shares, uint256 lastAccruedWeight) = IAlchemistV2(alchemist).positions(msg.sender, startingVault);

        if(!tokens.contains(startingVault)) {
            revert IllegalArgument("startingVault does not match user account tokens");
        }

		//At this point not too sure how to find exact amount of underlying tokens needed
		//Using positions now lasAccruedWeight

		// flashloan the amount of tokens needed to pay debt.

		// repay alchemist debt for specific underlying.

		// withdraw original loan amount to this contract. 

		// repay flash loan.

		// create new position with remainder.
		
	}

    /// @inheritdoc IMigrationTool
    function isVaultSupported(address yieldToken) external view override {
        if(!IAlchemistV2(alchemist).isSupportedYieldToken(yieldToken)) {
            revert IllegalArgument("Vault is not supported");
        }
    }

    /// @dev Checks that the 'msg.sender' is a valid alchemist account
    ///
    /// @dev 'msg.sender' must exist in the alchemist accounts or function will revert
    function _accountExists(address user) internal view {
		if(!alchemist.accounts(user)) {
			revert IllegalArgument("User does not exist within the alchemist");
		}
	}
}