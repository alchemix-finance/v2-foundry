// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

//remove later
import {console} from "forge-std/console.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "forge-std/stdlib.sol";

import {
    MigrationToolETH,
    InitializationParams as MigrtionInitializationParams
} from "../migration/MigrationToolETH.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

import {IAlToken} from "../interfaces/IAlToken.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {ICurveFactoryethpool} from "../interfaces/ICurveFactoryethpool.sol";


contract MigrationToolTest is DSTestPlus, stdCheats {
    //TODO sort these
    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant alToken = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant alchemistETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant curveFactoryPoolETH = 0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e;
    address constant invalidYieldToken = 0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant whitelist = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;
    address constant yvETH = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c;
    address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant rETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    IAlToken AlToken;
    IAlchemistV2 Alchemist;
    IWhitelist Whitelist;

    MigrationToolETH migration;

    function setUp() external {
        migration = new MigrationToolETH(MigrtionInitializationParams({
            alchemist:       alchemistETH,
            curvePool:       curveFactoryPoolETH
        }));

        AlToken = IAlToken(alToken);

        Alchemist = IAlchemistV2(alchemistETH);

        Whitelist = IWhitelist(whitelist);

        hevm.startPrank(admin);
        AlToken.setWhitelist(address(migration), true);
        AlToken.setCeiling(address(migration), MAX_INT);
        hevm.stopPrank();

        hevm.startPrank(owner);
        Whitelist.add(address(this));
        Whitelist.add(address(0xbeef));
        Whitelist.add(address(migration));
        Alchemist.setMaximumExpectedValue(wstETH, 2000e18);
        hevm.stopPrank();
    }

    function testUnsupportedVaults() external {
        expectIllegalArgumentError("Vault is not supported");
        migration.migrateVaults(invalidYieldToken, rETH, 100e18, 90e18);
        
        expectIllegalArgumentError("Vault is not supported");
        migration.migrateVaults(rETH , invalidYieldToken, 100e18, 90e18);
    }

    function testMigrationSameVault() external {
        tip(wETH, address(this), 2e18);
        
        // Create new position
        SafeERC20.safeApprove(wETH, alchemistETH, 2e18);
        Alchemist.depositUnderlying(yvETH, 2e18, address(this), 0);

        (uint256 shares, ) = Alchemist.positions(address(this), yvETH);
        Alchemist.mint(shares/2, address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        Alchemist.approveWithdraw(address(migration), yvETH, shares);
        Alchemist.approveMint(address(migration), shares);

        uint256 newShares = migration.migrateVaults(yvETH, yvETH, shares, 0);
        assertGt(newShares, shares * 9900 / BPS );
    }

    function testMigrationDifferentVault() external {
        tip(wETH, address(this), 10e18);
        
        // Create new position
        SafeERC20.safeApprove(wETH, alchemistETH, 1e18);
        Alchemist.depositUnderlying(yvETH, 1e18, address(this), 0);

        (uint256 shares, ) = Alchemist.positions(address(this), yvETH);
        Alchemist.mint(shares/2, address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        Alchemist.approveWithdraw(address(migration), yvETH, shares);
        Alchemist.approveMint(address(migration), shares);

        uint256 newShares = migration.migrateVaults(yvETH, wstETH, shares, 0);
        // TODO this seems too large a tolerance but the returns are not as good as usd vaults
        assertGt(newShares, shares * 9000 / BPS );
    }
}