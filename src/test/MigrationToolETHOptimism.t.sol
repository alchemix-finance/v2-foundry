// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {AlchemistV2} from "../AlchemistV2.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";

import {StaticAToken} from "../external/aave/StaticAToken.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    AAVETokenAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/aave/AAVETokenAdapter.sol";

import {MigrationTool} from "../migration/MigrationTool.sol";


import {IAlchemicToken} from "../interfaces/IAlchemicToken.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {ILendingPool} from "../interfaces/external/aave/ILendingPool.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {console} from "../../lib/forge-std/src/console.sol";

contract MigrationToolTestETH is DSTestPlus {
    address constant admin = 0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a;
    address constant alchemistETH = 0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4;
    address constant alETH = 0x3E29D3A9316dAB217754d13b28646B76607c5f04;
    address constant invalidYieldToken = 0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f;
    address constant owner = 0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a;
    address constant wETH = 0x4200000000000000000000000000000000000006;
    address constant whitelistETH = 0xc5fE32e46fD226364BFf7A035e8Ca2aBE390a68f;
    address constant wstETH = 0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb;
    address constant aWETH = 0x337B4B933d60F40CB57DD19AE834Af103F049810;
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    AlchemistV2 newAlchemistV2;
    StaticAToken staticAToken;

    IAlchemicToken AlETH;
    IAlchemistV2 AlchemistETH;
    IWhitelist WhitelistETH;

    MigrationTool migrationToolETH;

    function setUp() external {
        migrationToolETH = new MigrationTool(alchemistETH);

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
        AlchemistETH.setMaximumExpectedValue(aWETH, 200000000000000000000000);
        hevm.stopPrank();
    }

    function testMigrationDifferentVaultPartialShares() external {
        deal(wETH, address(this), 10e18);
        
        // Create new position
        SafeERC20.safeApprove(wETH, alchemistETH, 10e18);
        AlchemistETH.depositUnderlying(aWETH, 10e18, address(this), 0);
        (uint256 shares, ) = AlchemistETH.positions(address(this), aWETH);

        // Debt conversion in this case only divides by 1 so I left it out.
        uint256 underlyingValue = shares * AlchemistETH.getUnderlyingTokensPerShare(aWETH)  / 10**18;
        AlchemistETH.mint(underlyingValue / 2, address(this));

        // Debt after original mint
        (int256 firstPositionDebt, ) = AlchemistETH.accounts(address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        AlchemistETH.approveWithdraw(address(migrationToolETH), aWETH, shares);
        AlchemistETH.approveMint(address(migrationToolETH), underlyingValue);

        // Verify new position underlying value is within 0.1% of original
        (uint256 oldShares, ) = AlchemistETH.positions(address(this), aWETH);
        uint256 newShares = migrationToolETH.migrateVaults(aWETH, address(wstETH), shares / 2, 0, 0);
        uint256 newUnderlyingValue = (newShares + oldShares) * AlchemistETH.getUnderlyingTokensPerShare(address(wstETH)) / 10**18;
        assertGt(newUnderlyingValue, underlyingValue * 9999 / BPS);

        // Verify debts are the same
        (int256 secondPositionDebt, ) = AlchemistETH.accounts(address(this));
        assertEq(secondPositionDebt, firstPositionDebt);

        // Verify new position
        (uint256 sharesConfirmed, ) = AlchemistETH.positions(address(this), address(wstETH));
        assertEq(newShares, sharesConfirmed);

        // Verify old position
        (sharesConfirmed, ) = AlchemistETH.positions(address(this), aWETH);
        assertApproxEq(shares / 2, sharesConfirmed, 1);
    }

    function testMigrationDifferentVaultMaximumShares() external {
        deal(wETH, address(this), 10e18);

        // Create new position
        SafeERC20.safeApprove(wETH, alchemistETH, 10e18);
        AlchemistETH.depositUnderlying(aWETH, 10e18, address(this), 0);
        (uint256 shares, ) = AlchemistETH.positions(address(this), aWETH);

        // Debt conversion in this case only divides by 1 so I left it out.
        uint256 underlyingValue = shares * AlchemistETH.getUnderlyingTokensPerShare(aWETH)  / 10**18;
        AlchemistETH.mint(underlyingValue/2, address(this));

        // Debt after original mint
        (int256 firstPositionDebt, ) = AlchemistETH.accounts(address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        AlchemistETH.approveWithdraw(address(migrationToolETH), aWETH, shares);
        AlchemistETH.approveMint(address(migrationToolETH), underlyingValue);

        // Verify new position underlying value is within 0.01% of original
        uint256 newShares = migrationToolETH.migrateVaults(aWETH, address(wstETH), shares, 0, 0);
        uint256 newUnderlyingValue = newShares * AlchemistETH.getUnderlyingTokensPerShare(address(wstETH)) / 10**18;
        assertGt(newUnderlyingValue, underlyingValue * 9999 / BPS);

        // Verify debts are the same
        (int256 secondPositionDebt, ) = AlchemistETH.accounts(address(this));
        assertEq(secondPositionDebt, firstPositionDebt);

        // Verify new position
        (uint256 sharesConfirmed, ) = AlchemistETH.positions(address(this), address(wstETH));
        assertEq(newShares, sharesConfirmed);

        // Verify old position is gone
        (sharesConfirmed, ) = AlchemistETH.positions(address(this), aWETH);
        assertEq(0, sharesConfirmed);
    }
}