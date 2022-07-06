// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {AlchemistV2} from "../AlchemistV2.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";

import {StaticAToken} from "../external/aave/StaticAToken.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "forge-std/stdlib.sol";

import {
    AAVETokenAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/aave/AAVETokenAdapter.sol";

import {
    MigrationTool,
    InitializationParams as MigrationInitializationParams
} from "../migration/MigrationTool.sol";

import {IAlchemicToken} from "../interfaces/IAlchemicToken.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {ILendingPool} from "../interfaces/external/aave/ILendingPool.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

contract MigrationToolTestETH is DSTestPlus, stdCheats {
    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant alchemistETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant alETH = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant aWETH = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;
    address constant invalidYieldToken = 0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant rETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant whitelistETH = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;
    address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant yvETH = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c;
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    AlchemistV2 newAlchemistV2;
    StaticAToken staticAToken;

    IAlchemicToken AlETH;
    IAlchemistV2 AlchemistETH;
    ILendingPool lendingPool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IWhitelist WhitelistETH;

    MigrationTool migrationToolETH;

    function setUp() external {
        MigrationInitializationParams memory migrationParams = MigrationInitializationParams(alchemistETH);
        migrationToolETH = new MigrationTool(migrationParams);

        AlETH = IAlchemicToken(alETH);

        AlchemistETH = IAlchemistV2(alchemistETH);

        WhitelistETH = IWhitelist(whitelistETH);

        // Set contract permissions and ceiling for atokens
        hevm.startPrank(admin);
        AlETH.setWhitelist(address(migrationToolETH), true);
        AlETH.setCeiling(address(migrationToolETH), MAX_INT);
        hevm.stopPrank();

        // Set user and contract whitelist permission
        // Update deposit limits
        hevm.startPrank(owner);
        WhitelistETH.add(address(this));
        WhitelistETH.add(address(0xbeef));
        WhitelistETH.add(address(migrationToolETH));
        AlchemistETH.setMaximumExpectedValue(wstETH, 200000000000000000000000);
        AlchemistETH.setMaximumExpectedValue(yvETH, 200000000000000000000000);
        hevm.stopPrank();

        addAdapter(alchemistETH, aWETH, wETH, "aaWETH", "staticAaveWETH");
    }

    function testUnsupportedVaults() external {
        expectIllegalArgumentError("Vault is not supported");
        migrationToolETH.migrateVaults(invalidYieldToken, rETH, 100e18, 90e18, 0);
        
        expectIllegalArgumentError("Vault is not supported");
        migrationToolETH.migrateVaults(rETH , invalidYieldToken, 100e18, 90e18, 0);
    }

    function testMigrationSameVault() external {
        expectIllegalArgumentError("Vaults cannot be the same");
        migrationToolETH.migrateVaults(rETH, rETH, 100e18, 99e18, 0);

        expectIllegalArgumentError("Vaults cannot be the same");
        migrationToolETH.migrateVaults(wstETH, wstETH, 100e18, 90e18, 0);
    }

    function testMigrationDifferentVaultMaximumShares() external {
        tip(wETH, address(this), 10e18);

        // Create new position
        SafeERC20.safeApprove(wETH, alchemistETH, 10e18);
        AlchemistETH.depositUnderlying(yvETH, 10e18, address(this), 0);
        (uint256 shares, ) = AlchemistETH.positions(address(this), yvETH);

        // Debt before anything happens
        // Accounts for rounding errors
        (int256 startingDebt, ) = AlchemistETH.accounts(address(this));

        // Debt conversion in this case only divides by 1 so I left it out.
        uint256 underlyingValue = shares * AlchemistETH.getUnderlyingTokensPerShare(yvETH)  / 10**18;
        AlchemistETH.mint(underlyingValue/2, address(this));

        // Debt after original mint
        (int256 firstPositionDebt, ) = AlchemistETH.accounts(address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        AlchemistETH.approveWithdraw(address(migrationToolETH), yvETH, shares);
        AlchemistETH.approveMint(address(migrationToolETH), underlyingValue);

        // Verify new position underlying value is within 0.01% of original
        uint256 newShares = migrationToolETH.migrateVaults(yvETH, wstETH, shares, 0, 0);
        uint256 newUnderlyingValue = newShares * AlchemistETH.getUnderlyingTokensPerShare(wstETH) / 10**18;
        assertGt(newUnderlyingValue, underlyingValue * 9999 / BPS);

        // Verify debts are the same
        (int256 secondPositionDebt, ) = AlchemistETH.accounts(address(this));
        assertEq(secondPositionDebt, firstPositionDebt - startingDebt);

        // Verify new position
        (uint256 sharesConfirmed, ) = AlchemistETH.positions(address(this), wstETH);
        assertEq(newShares, sharesConfirmed);

        // Verify old position is gone
        (sharesConfirmed, ) = AlchemistETH.positions(address(this), yvETH);
        assertEq(0, sharesConfirmed);
    }

    function testMigrationDifferentVaultPartialShares() external {
        tip(wETH, address(this), 10e18);
        
        // Create new position
        SafeERC20.safeApprove(wETH, alchemistETH, 10e18);
        AlchemistETH.depositUnderlying(yvETH, 10e18, address(this), 0);
        (uint256 shares, ) = AlchemistETH.positions(address(this), yvETH);

        // Debt before anything happens
        // Accounts for rounding errors
        (int256 startingDebt, ) = AlchemistETH.accounts(address(this));

        // Debt conversion in this case only divides by 1 so I left it out.
        uint256 underlyingValue = shares * AlchemistETH.getUnderlyingTokensPerShare(yvETH)  / 10**18;
        AlchemistETH.mint(underlyingValue / 2, address(this));

        // Debt after original mint
        (int256 firstPositionDebt, ) = AlchemistETH.accounts(address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        AlchemistETH.approveWithdraw(address(migrationToolETH), yvETH, shares);
        AlchemistETH.approveMint(address(migrationToolETH), underlyingValue);

        // Verify new position underlying value is within 0.1% of original
        (uint256 oldShares, ) = AlchemistETH.positions(address(this), yvETH);
        uint256 newShares = migrationToolETH.migrateVaults(yvETH, wstETH, shares / 2, 0, 0);
        uint256 newUnderlyingValue = (newShares + oldShares) * AlchemistETH.getUnderlyingTokensPerShare(wstETH) / 10**18;
        assertGt(newUnderlyingValue, underlyingValue * 9999 / BPS);

        // Verify debts are the same
        (int256 secondPositionDebt, ) = AlchemistETH.accounts(address(this));
        assertEq(secondPositionDebt, firstPositionDebt - startingDebt);

        // Verify new position
        (uint256 sharesConfirmed, ) = AlchemistETH.positions(address(this), wstETH);
        assertEq(newShares, sharesConfirmed);

        // Verify old position
        (sharesConfirmed, ) = AlchemistETH.positions(address(this), yvETH);
        assertApproxEq(shares / 2, sharesConfirmed, 1);
    }

    function testMigrationDifferentVaultMaximumSharesAAVE() external {
        tip(wETH, address(this), 10e18);

        // Create new position
        SafeERC20.safeApprove(wETH, alchemistETH, 10e18);
        AlchemistETH.depositUnderlying(yvETH, 10e18, address(this), 0);
        (uint256 shares, ) = AlchemistETH.positions(address(this), yvETH);

        // Debt before anything happens
        // Accounts for rounding errors
        (int256 startingDebt, ) = AlchemistETH.accounts(address(this));

        // Debt conversion in this case only divides by 1 so I left it out.
        uint256 underlyingValue = shares * AlchemistETH.getUnderlyingTokensPerShare(yvETH)  / 10**18;
        AlchemistETH.mint(underlyingValue/2, address(this));

        // Debt after original mint
        (int256 firstPositionDebt, ) = AlchemistETH.accounts(address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        AlchemistETH.approveWithdraw(address(migrationToolETH), yvETH, shares);
        AlchemistETH.approveMint(address(migrationToolETH), underlyingValue);

        // Verify new position underlying value is within 0.01% of original
        uint256 newShares = migrationToolETH.migrateVaults(yvETH, address(staticAToken), shares, 0, 0);
        uint256 newUnderlyingValue = newShares * AlchemistETH.getUnderlyingTokensPerShare(address(staticAToken)) / 10**18;
        assertGt(newUnderlyingValue, underlyingValue * 9999 / BPS);

        // Verify debts are the same
        (int256 secondPositionDebt, ) = AlchemistETH.accounts(address(this));
        assertEq(secondPositionDebt, firstPositionDebt - startingDebt);

        // Verify new position
        (uint256 sharesConfirmed, ) = AlchemistETH.positions(address(this), address(staticAToken));
        assertEq(newShares, sharesConfirmed);

        // Verify old position is gone
        (sharesConfirmed, ) = AlchemistETH.positions(address(this), yvETH);
        assertEq(0, sharesConfirmed);
    }

    function addAdapter(address alchemist, address aToken, address underlyingToken, string memory symbol, string memory name) public {
        staticAToken = new StaticAToken(
            lendingPool,
            aToken,
            name,
            symbol
        );

        AAVETokenAdapter newAdapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:       alchemist,
            token:           address(staticAToken),
            underlyingToken: underlyingToken
        }));

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(newAdapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });

        hevm.startPrank(owner);
        IAlchemistV2(alchemist).addYieldToken(address(staticAToken), ytc);
        IAlchemistV2(alchemist).setYieldTokenEnabled(address(staticAToken), true);
        hevm.stopPrank();
    }

}