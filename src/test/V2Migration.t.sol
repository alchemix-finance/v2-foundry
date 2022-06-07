// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "forge-std/console.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";

import {AlchemistV2} from "../AlchemistV2.sol";
import {PausableTransmuterConduit} from "../PausableTransmuterConduit.sol";
import {TransferAdapter} from "../adapters/V1/TransferAdapter.sol";

import {IAlchemicToken} from "../interfaces/IAlchemicToken.sol";
import {IAlchemistV1} from "../interfaces/IAlchemistV1.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IProxyAdmin} from "../interfaces/external/IProxyAdmin.sol";
import {ITransmuterV1} from "../interfaces/ITransmuterV1.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {FixedPointMath} from "../libraries/FixedPointMath.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";

contract V2MigrationTest is DSTestPlus, stdCheats {
    uint256 constant BPS = 10000;
    address constant alchemistV1USDAddress = 0xc21D353FF4ee73C572425697f4F5aaD2109fe35b;
    address constant alchemistV2USDAddress = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant alUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant governance = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant proxyAdminAddress = 0xE0fC5CB7665041CdA26969A2D1ceb5cD5046347d;
    address constant transmuterV1Address = 0x9735F7d3Ea56b454b24fFD74C58E9bD85cfaD31B;
    address constant treasury = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant whitelistV2Address = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    address constant yvDAI = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;

    IAlchemicToken alchemicToken = IAlchemicToken(alUSD);
    IAlchemistV1 alchemistV1USD = IAlchemistV1(alchemistV1USDAddress);
    IAlchemistV2 alchemistV2USD = IAlchemistV2(alchemistV2USDAddress);
    IProxyAdmin proxyAdmin = IProxyAdmin(proxyAdminAddress);
    IWhitelist whitelistV2 = IWhitelist(whitelistV2Address);

    AlchemistV2 newAlchemistV2; 
    PausableTransmuterConduit pausableTransmuterConduit;
    TransferAdapter transferAdapter;

    function setUp() external {
        newAlchemistV2 = new AlchemistV2();
        pausableTransmuterConduit = new PausableTransmuterConduit(governance, DAI, alchemistV1USDAddress, transmuterV1Address);
        transferAdapter = new TransferAdapter(alchemistV1USDAddress, alUSD, DAI, yvDAI, alchemistV1USDAddress, alchemistV2USDAddress);

        // Allow adapter to deposit underlying tokens into V2.
        // & Set adapter address in the alchemist V2.
        // & Upgrade alchemist V2 to new version with debt transfer.
        // & Swap to new transmuter conduit for V1.
        hevm.startPrank(governance);
        proxyAdmin.upgrade(alchemistV2USDAddress, address(newAlchemistV2));
        whitelistV2.add(address(transferAdapter));
        alchemistV2USD.setTransferAdapterAddress(address(transferAdapter));
        alchemistV1USD.setTransmuter(address(pausableTransmuterConduit));
        hevm.stopPrank();

        // Start a position in V1 as 0xbeef and go into debt
        tip(DAI, address(0xbeef), 200e18);
        hevm.startPrank(address(0xbeef), address(0xbeef));
        SafeERC20.safeApprove(DAI, alchemistV1USDAddress, 100e18);
        alchemistV1USD.deposit(100e18);
        // Mint throws 'unhealthy collateralization ratio' later when withdrawing.
        alchemistV1USD.mint(10e18);
        hevm.stopPrank();
    }

    function testMigrateFunds() external {
        // V1 debt before migration
        uint256 originalDebt = alchemistV1USD.getCdpTotalDebt(address(0xbeef));

        // Pull funds from current vault and flush to the transfer adapter
        hevm.startPrank(governance);
        (uint256 withdrawnAmount, ) = alchemistV1USD.recallAll(1);
        alchemistV1USD.migrate(transferAdapter);
        uint256 flushed = alchemistV1USD.flush();
        hevm.stopPrank();
        // Contract may have previous balance so check if flushed is greater than or equal to withdrawn amount
        assertGt(flushed, withdrawnAmount - 1);

        // Pause the transmuter.
        hevm.prank(governance);
        pausableTransmuterConduit.pauseTransmuter(true);
        // Stop V1 from minting more alUSD.
        hevm.prank(treasury);
        alchemicToken.setWhitelist(alchemistV1USDAddress, false);
        // Pause the alchemist.
        hevm.prank(governance);
        alchemistV1USD.setEmergencyExit(true);
        // Test that only withdraw works after these steps.
        hevm.startPrank(address(0xbeef), address(0xbeef));
        hevm.expectRevert("Transmuter is currently paused!");
        alchemistV1USD.liquidate(1);
        hevm.expectRevert("Transmuter is currently paused!");
        alchemistV1USD.harvest(1);
        // hevm.expectRevert("Transmuter is currently paused!");
        // SafeERC20.safeApprove(DAI, alchemistV1USDAddress, 100);
        // alchemistV1USD.repay(10,1);
        hevm.expectRevert("AlUSD: Alchemist is not whitelisted");
        alchemistV1USD.mint(5e18);
        hevm.expectRevert("emergency pause enabled");
        alchemistV1USD.deposit(5e18);
        hevm.stopPrank();

        // Roll chain ahead
        hevm.roll(block.number + 10);

        // User withdraws 
        hevm.startPrank(address(0xbeef), address(0xbeef));
        // Withdraw too much and expect revert
        hevm.expectRevert("TransferAdapter: Amount must be 1");
        alchemistV1USD.withdraw(10);
        // Withdraw correctly using 1
        alchemistV1USD.withdraw(1);
        // Withdraw again should revert
        hevm.expectRevert("User has already migrated");
        alchemistV1USD.withdraw(1);
        hevm.stopPrank();

        // Debts must be the same as debt in V1
        (int256 V2Debt, ) = alchemistV2USD.accounts(address(0xbeef));
        assertEq(int256(originalDebt), V2Debt);
    }
}
