// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

//remove later
import {console} from "forge-std/console.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "forge-std/stdlib.sol";

import {
    MigrationToolUSD,
    InitializationParams as MigrtionInitializationParams
} from "../migration/MigrationToolUSD.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

import {IAlToken} from "../interfaces/IAlToken.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {ICurveMetapool} from "../interfaces/ICurveMetapool.sol";


contract MigrationToolTest is DSTestPlus, stdCheats {
    // TODO sort
    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant alToken = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address constant alchemistUSD = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant curveMetapool = 0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c;
    address constant curveThreePool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant invalidYieldToken = 0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant whitelist = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    address constant yvDAI = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;
    address constant yvUSDC = 0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE;
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    IAlToken AlToken;
    IAlchemistV2 Alchemist;
    IWhitelist Whitelist;

    MigrationToolUSD migration;

    function setUp() external {
        migration = new MigrationToolUSD(MigrtionInitializationParams({
            alchemist:       alchemistUSD,
            curveMetapool:  curveMetapool,
            curveThreePool:  curveThreePool
        }));

        AlToken = IAlToken(alToken);

        Alchemist = IAlchemistV2(alchemistUSD);

        Whitelist = IWhitelist(whitelist);

        hevm.startPrank(admin);
        AlToken.setWhitelist(address(migration), true);
        AlToken.setCeiling(address(migration), MAX_INT);
        hevm.stopPrank();

        hevm.startPrank(owner);
        Whitelist.add(address(this));
        Whitelist.add(address(0xbeef));
        Whitelist.add(address(migration));
        hevm.stopPrank();
    }

    function testUnsupportedVaults() external {
        expectIllegalArgumentError("Vault is not supported");
        migration.migrateVaults(invalidYieldToken, yvDAI, 100e18, 90e18);
        
        expectIllegalArgumentError("Vault is not supported");
        migration.migrateVaults(yvDAI , invalidYieldToken, 100e18, 90e18);
    }

    function testMigrationSameVault() external {
        tip(DAI, address(this), 200e18);
        
        // Create new position
        SafeERC20.safeApprove(DAI, alchemistUSD, 100e18);
        Alchemist.depositUnderlying(yvDAI, 100e18, address(this), 0);

        (uint256 shares, ) = Alchemist.positions(address(this), yvDAI);
        Alchemist.mint(shares/2, address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        // TODO See if there is a way for the tool to approve itself
        Alchemist.approveWithdraw(address(migration), yvDAI, shares);
        Alchemist.approveMint(address(migration), shares);

        (uint256 newShares, uint256 userPayment) = migration.migrateVaults(yvDAI, yvDAI, shares, 0);
        assertGt(newShares, shares * 9900 / BPS );
    }

    function testMigrationDifferentVault() external {
        // TODO test with different vaults once they are ready
    }

    function testMigrationDifferentUnderlying() external {
        tip(DAI, address(this), 200e18);
        
        // Create new position
        SafeERC20.safeApprove(DAI, alchemistUSD, 100e18);
        Alchemist.depositUnderlying(yvDAI, 100e18, address(this), 0);

        (uint256 shares, ) = Alchemist.positions(address(this), yvDAI);
        Alchemist.mint(shares/2, address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        // TODO See if there is a way for the tool to approve itself
        Alchemist.approveWithdraw(address(migration), yvDAI, shares);
        Alchemist.approveMint(address(migration), shares);

        (uint256 newShares, uint256 userPayment) = migration.migrateVaults(yvDAI, yvUSDC, shares, 0);
        assertGt(newShares * 1e12, shares * 9900 / BPS );

        // TODO add assert to see if alchemist has position for new currency
    }
}