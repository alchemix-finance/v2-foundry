// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "forge-std/stdlib.sol";

import {
    MigrationTool,
    InitializationParams as MigrtionInitializationParams
} from "../migration/MigrationTool.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract MingrationToolTest is DSTestPlus, stdCheats {
    address constant alchemistUSD = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant invalidYieldToken = 0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f;
    address constant yvDAI = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;
    address constant yvUSDC = 0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE;
    uint256 constant BPS = 10000;

    MingrationTool migration;

    function setUp() external {
        migration = new MingrationTool(MigrtionInitializationParams({
            alchemist:       alchemistUSD;
        }));
    }

    function testInvalidAccount() external {
        // TODO use address of account that does not exist
        // Expect revert
        migration.migrateVaults();
    }

    function testUnsupportedVaults() external {
        // Expect revert
        migration.migrateVaults(invalidYieldToken, yvDAI, 100e18, 90e18);
        migration.migrateVaults(yvDAI , invalidYieldToken, 100e18, 90e18);
    }

    function testMigration() external {
        // TODO write the full migrate function and test
        uint256 underlyingValue = migration.migrateVaults(yvDAI, yvUSDC, 100e18, 90e18);
    }
}