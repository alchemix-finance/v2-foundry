// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

//remove later
import {console} from "forge-std/console.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "forge-std/stdlib.sol";

import {
    MigrationTool,
    InitializationParams as MigrtionInitializationParams
} from "../migration/MigrationTool.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

import {IAlToken} from "../interfaces/IAlToken.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {ICurveMetapool} from "../interfaces/ICurveMetapool.sol";


contract MigrationToolTest is DSTestPlus, stdCheats {
    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant alchemistETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant alchemistUSD = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant alETH = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant alUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address constant curveMetapool = 0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c;
    address constant curveThreePool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant invalidYieldToken = 0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant rETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant whitelistETH = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;
    address constant whitelistUSD = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant yvDAI = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;
    address constant yvETH = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c;
    address constant yvUSDC = 0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE;
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;


    IAlToken AlUSD;
    IAlToken AlETH;
    IAlchemistV2 AlchemistUSD;
    IAlchemistV2 AlchemistETH;
    IWhitelist WhitelistUSD;
    IWhitelist WhitelistETH;

    MigrationTool migrationToolETH;
    MigrationTool migrationToolUSD;

    function setUp() external {
        migrationToolETH = new MigrationTool(MigrtionInitializationParams({
            alchemist:       alchemistETH,
            curveMetapool:  curveMetapool,
            curveThreePool:  curveThreePool
        }));

        migrationToolUSD = new MigrationTool(MigrtionInitializationParams({
            alchemist:       alchemistUSD,
            curveMetapool:  curveMetapool,
            curveThreePool:  curveThreePool
        }));

        AlUSD = IAlToken(alUSD);
        AlETH = IAlToken(alETH);

        AlchemistUSD = IAlchemistV2(alchemistUSD);
        AlchemistETH = IAlchemistV2(alchemistETH);

        WhitelistUSD = IWhitelist(whitelistUSD);
        WhitelistETH = IWhitelist(whitelistETH);

        hevm.startPrank(admin);
        AlETH.setWhitelist(address(migrationToolETH), true);
        AlETH.setCeiling(address(migrationToolETH), MAX_INT);
        AlUSD.setWhitelist(address(migrationToolUSD), true);
        AlUSD.setCeiling(address(migrationToolUSD), MAX_INT);
        hevm.stopPrank();

        hevm.startPrank(owner);
        WhitelistETH.add(address(this));
        WhitelistETH.add(address(0xbeef));
        WhitelistETH.add(address(migrationToolETH));
        WhitelistUSD.add(address(this));
        WhitelistUSD.add(address(0xbeef));
        WhitelistUSD.add(address(migrationToolUSD));
        AlchemistETH.setMaximumExpectedValue(wstETH, 2000000000000000000000);
        hevm.stopPrank();
    }

    function testUnsupportedVaults() external {
        expectIllegalArgumentError("Vault is not supported");
        migrationToolUSD.migrateVaults(invalidYieldToken, yvDAI, 100e18, 99e18);
        
        expectIllegalArgumentError("Vault is not supported");
        migrationToolUSD.migrateVaults(yvDAI , invalidYieldToken, 100e18, 99e18);

        expectIllegalArgumentError("Vault is not supported");
        migrationToolETH.migrateVaults(invalidYieldToken, rETH, 100e18, 90e18);
        
        expectIllegalArgumentError("Vault is not supported");
        migrationToolETH.migrateVaults(rETH , invalidYieldToken, 100e18, 90e18);
    }

    function testMigrationSameVault() external {
        expectIllegalArgumentError("Vaults cannot be the same");
        migrationToolUSD.migrateVaults(yvDAI, yvDAI, 100e18, 99e18);

        expectIllegalArgumentError("Vaults cannot be the same");
        migrationToolETH.migrateVaults(yvETH, yvETH, 100e18, 90e18);
    }

    function testMigrationDifferentUnderlying() external {
        tip(DAI, address(this), 100e18);
        
        // Create new position
        SafeERC20.safeApprove(DAI, alchemistUSD, 100e18);
        AlchemistUSD.depositUnderlying(yvDAI, 100e18, address(this), 0);
        (uint256 shares, ) = AlchemistUSD.positions(address(this), yvDAI);
        uint256 underlyingValue = shares * AlchemistUSD.getUnderlyingTokensPerShare(yvDAI);
        AlchemistUSD.mint(shares/2, address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        AlchemistUSD.approveWithdraw(address(migrationToolUSD), yvDAI, shares);
        AlchemistUSD.approveMint(address(migrationToolUSD), shares);

        // Verify new position underlying value is within 0.1% of original
        uint256 newShares = migrationToolUSD.migrateVaults(yvDAI, yvUSDC, shares, 0);
        uint256 newUnderlyingValue = newShares * AlchemistUSD.getUnderlyingTokensPerShare(yvUSDC);
        assertGt(newUnderlyingValue * 1e12, underlyingValue * 9990 / BPS / 1e12);

        // Verify new position
        (uint256 sharesConfirmed, ) = AlchemistUSD.positions(address(this), yvUSDC);
        assertEq(newShares, sharesConfirmed);

        // Verify old position is gone
        (sharesConfirmed, ) = AlchemistUSD.positions(address(this), yvDAI);
        assertEq(0, sharesConfirmed);
    }

    function testMigrationDifferentVault() external {
        tip(wETH, address(this), 10e18);
        
        // Create new position
        SafeERC20.safeApprove(wETH, alchemistETH, 10e18);
        AlchemistETH.depositUnderlying(yvETH, 10e18, address(this), 0);

        (uint256 shares, ) = AlchemistETH.positions(address(this), yvETH);
        uint256 underlyingValue = shares * AlchemistETH.getUnderlyingTokensPerShare(yvETH);
        AlchemistETH.mint(shares/2, address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        AlchemistETH.approveWithdraw(address(migrationToolETH), yvETH, shares);
        AlchemistETH.approveMint(address(migrationToolETH), shares);

        // Verify new position underlying value is within 0.1% of original
        uint256 newShares = migrationToolETH.migrateVaults(yvETH, wstETH, shares, 0);
        uint256 newUnderlyingValue = newShares * AlchemistETH.getUnderlyingTokensPerShare(wstETH);
        assertGt(newUnderlyingValue, underlyingValue * 9990 / BPS);

        // Verify new position
        (uint256 sharesConfirmed, ) = AlchemistETH.positions(address(this), wstETH);
        assertEq(newShares, sharesConfirmed);

        // Verify old position is gone
        (sharesConfirmed, ) = AlchemistETH.positions(address(this), yvETH);
        assertEq(0, sharesConfirmed);
    }
}