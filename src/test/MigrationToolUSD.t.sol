// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {AlchemistV2} from "../AlchemistV2.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";

import {StaticAToken} from "../external/aave/StaticAToken.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";

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

contract MigrationToolTestUSD is DSTestPlus, stdCheats {
    address constant aDAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant alchemistUSD = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant alUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address constant aUSDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address constant aUSDT = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant invalidYieldToken = 0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant whitelistUSD = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    address constant yvDAI = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;
    address constant yvUSDC = 0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE;
    address constant yvUSDT = 0x7Da96a3891Add058AdA2E826306D812C638D87a7;
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    AlchemistV2 newAlchemistV2;
    StaticAToken staticATokenDAI;
    StaticAToken staticATokenUSDC;
    StaticAToken staticATokenUSDT;

    IAlchemicToken AlUSD;
    IAlchemistV2 AlchemistUSD;
    ILendingPool lendingPool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IWhitelist WhitelistUSD;

    MigrationTool migrationToolUSD;

    function setUp() external {
        MigrationInitializationParams memory migrationParams = MigrationInitializationParams(alchemistUSD, new address[](3));
        migrationParams.collateralAddresses[0] = (0x6B175474E89094C44Da98b954EedeAC495271d0F);
        migrationParams.collateralAddresses[1] = (0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        migrationParams.collateralAddresses[2] = (0xdAC17F958D2ee523a2206206994597C13D831ec7);
        migrationToolUSD = new MigrationTool(migrationParams);

        AlUSD = IAlchemicToken(alUSD);

        AlchemistUSD = IAlchemistV2(alchemistUSD);

        WhitelistUSD = IWhitelist(whitelistUSD);

        // Set contract permissions and ceiling for alchemic tokens
        hevm.startPrank(admin);
        AlUSD.setWhitelist(address(migrationToolUSD), true);
        AlUSD.setCeiling(address(migrationToolUSD), MAX_INT);
        hevm.stopPrank();

        // Set user and contract whitelist permissions
        // Update deposit limits
        hevm.startPrank(owner);
        WhitelistUSD.add(address(this));
        WhitelistUSD.add(address(0xbeef));
        WhitelistUSD.add(address(migrationToolUSD));
        AlchemistUSD.setMaximumExpectedValue(yvUSDT, MAX_INT);
        hevm.stopPrank();

        staticATokenDAI = new StaticAToken(
            lendingPool,
            aDAI,
            "saDAI",
            "staticAaveDAI"
        );

        staticATokenUSDT = new StaticAToken(
            lendingPool,
            aUSDT,
            "saUSDT",
            "staticAaveUSDT"
        );

        staticATokenUSDC = new StaticAToken(
            lendingPool,
            aUSDC,
            "saUSDC",
            "staticAaveUSDC"
        );

        newAlchemistV2 = new AlchemistV2();

        hevm.etch(alchemistUSD, address(newAlchemistV2).code);

        addAdapter(alchemistUSD, address(staticATokenDAI), DAI);
        addAdapter(alchemistUSD, address(staticATokenUSDC), USDC);
        addAdapter(alchemistUSD, address(staticATokenUSDT), USDT);
    }

    function testUnsupportedVaults() external {
        expectIllegalArgumentError("Yield token is not supported");
        migrationToolUSD.migrateVaults(invalidYieldToken, yvDAI, 100e18, 99e18, 0);
        
        expectIllegalArgumentError("Yield token is not supported");
        migrationToolUSD.migrateVaults(yvDAI , invalidYieldToken, 100e18, 99e18, 0);
    }

    function testMigrationSameVault() external {
        expectIllegalArgumentError("Yield tokens cannot be the same");
        migrationToolUSD.migrateVaults(yvDAI, yvDAI, 100e18, 99e18, 0);
    }

    function testMigrationDifferentUnderlying() external {
        expectIllegalArgumentError("Cannot swap between different collaterals");
        migrationToolUSD.migrateVaults(yvDAI, yvUSDC, 100e18, 90e18, 0);
    }

    function testMigrateMaxDAI() external {
        migrationDifferentVaultMaximumShares(1000e18, yvDAI, DAI, address(staticATokenDAI), 18);
    }

    function testMigratePartialDAI() external {
        migrationDifferentVaultPartialShares(1000e18, yvDAI, DAI, address(staticATokenDAI), 18);
    }

    function testMigrateMaxUSDT() external {
        migrationDifferentVaultMaximumShares(1000e6, yvUSDT, USDT, address(staticATokenUSDT), 6);
    }

    function testMigratePartialUSDT() external {
        migrationDifferentVaultPartialShares(1000e6, yvUSDT, USDT, address(staticATokenUSDT), 6);
    }

    function testMigrateMaxUSDC() external {
        migrationDifferentVaultMaximumShares(1000e6, yvUSDC, USDC, address(staticATokenUSDC), 6);
    }

    function testMigratePartialUSDC() external {
        migrationDifferentVaultPartialShares(1000e6, yvUSDC, USDC, address(staticATokenUSDC), 6);
    }

    function testMigrationFuzz(uint256 p1, uint256 p2, uint256 p3) external {
        hevm.assume(p1 >= 1e18);
        hevm.assume(p2 >= 1e6);
        hevm.assume(p3 >= 1e6);

        // Pre deposit a random position
        while (p1 > 2000000e18) {
            p1 = p1 / 2;
        }
        // Create new position
         tip(DAI, address(this), p1);
        SafeERC20.safeApprove(DAI, alchemistUSD, p1);
        AlchemistUSD.depositUnderlying(yvDAI, p1, address(this), 0);
        (uint256 shares, ) = AlchemistUSD.positions(address(this), yvDAI);
        uint256 underlyingValue = shares * AlchemistUSD.getUnderlyingTokensPerShare(yvDAI)  / 10**18;
        AlchemistUSD.mint(underlyingValue/2, address(this));

        // Pre deposit a random position
        while (p2 > 2000000e6) {
            p2 = p2 / 2;
        }
        // Create new position
         tip(USDC, address(this), p2);
        SafeERC20.safeApprove(USDC, alchemistUSD, p2);
        AlchemistUSD.depositUnderlying(yvUSDC, p2, address(this), 0);
        (shares, ) = AlchemistUSD.positions(address(this), yvUSDC);
        underlyingValue = shares * AlchemistUSD.getUnderlyingTokensPerShare(yvUSDC)  / 10**6;
        uint256 debtValue = underlyingValue * 10**(18 - 6);
        AlchemistUSD.mint(debtValue/2, address(this));

        // Migrate random amount
        while (p3 > 2000000e6) {
            p3 = p3 / 2;
        }

        migrationDifferentVaultMaximumShares(p3, yvUSDT, USDT, address(staticATokenUSDT), 6);
    }

    function testZap() external {
        tip(DAI, address(this), 1000e18);

        // Create new position
        SafeERC20.safeApprove(DAI, alchemistUSD, 1000e18);
        AlchemistUSD.depositUnderlying(yvDAI, 1000e18, address(this), 0);
        (uint256 shares, ) = AlchemistUSD.positions(address(this), yvDAI);

        // Debt conversion in this case only divides by 1 so I left it out.
        uint256 underlyingValue = shares * AlchemistUSD.getUnderlyingTokensPerShare(yvDAI)  / 10**18;

        // Debt after original mint
        (int256 firstPositionDebt, ) = AlchemistUSD.accounts(address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        AlchemistUSD.approveWithdraw(address(migrationToolUSD), yvDAI, shares);
        AlchemistUSD.approveMint(address(migrationToolUSD), underlyingValue);

        // Verify new position underlying value is within 0.01% of original
        uint256 newShares = migrationToolUSD.migrateVaults(yvDAI, address(staticATokenDAI), shares, 0, 0);
        uint256 newUnderlyingValue = newShares * AlchemistUSD.getUnderlyingTokensPerShare(address(staticATokenDAI)) / 10**18;
        assertGt(newUnderlyingValue, underlyingValue * 9999 / BPS);

        // Verify debts are the same
        (int256 secondPositionDebt, ) = AlchemistUSD.accounts(address(this));
        assertEq(secondPositionDebt, firstPositionDebt);

        // Verify new position
        (uint256 sharesConfirmed, ) = AlchemistUSD.positions(address(this), address(staticATokenDAI));
        assertEq(newShares, sharesConfirmed);

        // Verify old position is gone
        (sharesConfirmed, ) = AlchemistUSD.positions(address(this), yvDAI);
        assertEq(0, sharesConfirmed);
    }

    function migrationDifferentVaultMaximumShares(uint256 amount, address yearnToken, address underlying, address staticToken, uint256 decimals) public {
        tip(underlying, address(this), amount);

        // Create new position
        SafeERC20.safeApprove(underlying, alchemistUSD, amount);
        AlchemistUSD.depositUnderlying(yearnToken, amount, address(this), 0);
        (uint256 shares, ) = AlchemistUSD.positions(address(this), yearnToken);

        // Debt conversion in this case only divides by 1 so I left it out.
        uint256 underlyingValue = shares * AlchemistUSD.getUnderlyingTokensPerShare(yearnToken)  / 10**decimals;
        uint256 debtValue = underlyingValue * 10**(18 - decimals);
        AlchemistUSD.mint(debtValue/2, address(this));
        
        // Debt after original mint
        (int256 firstPositionDebt, ) = AlchemistUSD.accounts(address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        AlchemistUSD.approveWithdraw(address(migrationToolUSD), yearnToken, shares);
        AlchemistUSD.approveMint(address(migrationToolUSD), debtValue);

        // Verify new position underlying value is within 0.01% of original
        uint256 newShares = migrationToolUSD.migrateVaults(yearnToken, staticToken, shares, 0, 0);
        uint256 newUnderlyingValue = newShares * AlchemistUSD.getUnderlyingTokensPerShare(staticToken) / 10**decimals;
        assertGt(newUnderlyingValue, underlyingValue * 9999 / BPS);

        // Verify debts are the same
        (int256 secondPositionDebt, ) = AlchemistUSD.accounts(address(this));
        assertEq(secondPositionDebt, firstPositionDebt);

        // Verify new position
        (uint256 sharesConfirmed, ) = AlchemistUSD.positions(address(this), staticToken);
        assertEq(newShares, sharesConfirmed);

        // Verify old position is gone
        (sharesConfirmed, ) = AlchemistUSD.positions(address(this), yearnToken);
        assertEq(0, sharesConfirmed);
    }

    function migrationDifferentVaultPartialShares(uint256 amount, address yearnToken, address underlying, address staticToken, uint256 decimals) public {
        tip(underlying, address(this), amount);
        
        // Create new position
        SafeERC20.safeApprove(underlying, alchemistUSD, amount);
        AlchemistUSD.depositUnderlying(yearnToken, amount, address(this), 0);
        (uint256 shares, ) = AlchemistUSD.positions(address(this), yearnToken);

        // Debt conversion in this case only divides by 1 so I left it out.
        uint256 underlyingValue = shares * AlchemistUSD.getUnderlyingTokensPerShare(yearnToken)  / 10**decimals;
        uint256 debtValue = underlyingValue * 10**(18 - decimals);
        AlchemistUSD.mint(debtValue/2, address(this));

        // Debt after original mint
        (int256 firstPositionDebt, ) = AlchemistUSD.accounts(address(this));

        // Approve the migration tool to withdraw and mint on behalf of the user
        AlchemistUSD.approveWithdraw(address(migrationToolUSD), yearnToken, shares);
        AlchemistUSD.approveMint(address(migrationToolUSD), debtValue);

        // Verify new position underlying value is within 0.1% of original
        (uint256 oldShares, ) = AlchemistUSD.positions(address(this), yearnToken);
        uint256 newShares = migrationToolUSD.migrateVaults(yearnToken, staticToken, shares / 2, 0, 0);
        uint256 newUnderlyingValue = (newShares + oldShares) * AlchemistUSD.getUnderlyingTokensPerShare(staticToken) / 10**decimals;
        assertGt(newUnderlyingValue, underlyingValue * 9999 / BPS);

        // Verify debts are the same
        (int256 secondPositionDebt, ) = AlchemistUSD.accounts(address(this));
        assertEq(secondPositionDebt, firstPositionDebt);

        // Verify new position
        (uint256 sharesConfirmed, ) = AlchemistUSD.positions(address(this), staticToken);
        assertEq(newShares, sharesConfirmed);

        // Verify old position
        (sharesConfirmed, ) = AlchemistUSD.positions(address(this), yearnToken);
        assertApproxEq(shares / 2, sharesConfirmed, 1);
    }

    function addAdapter(address alchemist, address aToken, address underlyingToken) public {
        AAVETokenAdapter newAdapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:       alchemist,
            token:           aToken,
            underlyingToken: underlyingToken
        }));

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(newAdapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });

        hevm.startPrank(owner);
        IAlchemistV2(alchemist).addYieldToken(aToken, ytc);
        IAlchemistV2(alchemist).setYieldTokenEnabled(aToken, true);
        hevm.stopPrank();
    }

}