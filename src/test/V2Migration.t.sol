// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "forge-std/console.sol";

import {V1AddressList} from "../addresses.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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
    uint256 constant scalar = 10**18;
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
        transferAdapter = new TransferAdapter(alchemistV1USDAddress, alUSD, DAI, yvDAI, alchemistV1USDAddress, alchemistV2USDAddress, 1186);

        // Allow adapter to deposit underlying tokens into V2
        // & Set adapter address in the alchemist V2
        // & Upgrade alchemist V2 to new version with debt transfer
        // & Swap to new transmuter conduit for V1
        // & Update maximum value for yvDAI deposit
        hevm.startPrank(governance);
        proxyAdmin.upgrade(alchemistV2USDAddress, address(newAlchemistV2));
        whitelistV2.add(address(transferAdapter));
        alchemistV2USD.setTransferAdapterAddress(address(transferAdapter));
        alchemistV1USD.setTransmuter(address(pausableTransmuterConduit));
        alchemistV2USD.setMaximumExpectedValue(yvDAI, 4000000000000000000000000000);
        hevm.stopPrank();

        // Start a position in V1 as 0xbeef and go into debt
        tip(DAI, address(0xbeef), 200e18);
        hevm.startPrank(address(0xbeef), address(0xbeef));
        SafeERC20.safeApprove(DAI, alchemistV1USDAddress, 100e18);
        alchemistV1USD.deposit(100e18);
        alchemistV1USD.mint(10e18);
        hevm.stopPrank();
    }

    function testMigrateSingleUserFunds() external {
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

        // Pause the transmuter
        hevm.prank(governance);
        pausableTransmuterConduit.pauseTransmuter(true);
        // Stop V1 from minting more alUSD
        hevm.prank(treasury);
        alchemicToken.setWhitelist(alchemistV1USDAddress, false);
        // Pause the alchemist.
        hevm.prank(governance);
        alchemistV1USD.setEmergencyExit(true);
        // Test that only withdraw works after these steps.
        hevm.startPrank(address(0xbeef), address(0xbeef));
        expectIllegalStateError("Transmuter is currently paused!");
        alchemistV1USD.liquidate(1);
        expectIllegalStateError("Transmuter is currently paused!");
        alchemistV1USD.harvest(1);
        SafeERC20.safeApprove(DAI, alchemistV1USDAddress, 10e18);
        expectIllegalStateError("Transmuter is currently paused!");
        alchemistV1USD.repay(10e18,10e18);
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
        hevm.expectRevert(abi.encodeWithSignature("IllegalArgument(string)", "TransferAdapter: Amount must be 1"));
        alchemistV1USD.withdraw(10);
        // Withdraw correctly using 1
        alchemistV1USD.withdraw(1);
        // Withdraw again should revert
        hevm.expectRevert(abi.encodeWithSignature("IllegalState(string)", "User has already migrated"));
        alchemistV1USD.withdraw(1);
        hevm.stopPrank();

        // Debts must be the same as debt in V1
        (int256 V2Debt, ) = alchemistV2USD.accounts(address(0xbeef));
        assertEq(int256(originalDebt), V2Debt);
        // Verigy underlying value of position in V2
        (uint256 shares, uint256 weight) = alchemistV2USD.positions(address(0xbeef), yvDAI);
        uint256 underlyingValue = shares * alchemistV2USD.getUnderlyingTokensPerShare(yvDAI) / scalar;
        assertApproxEq(underlyingValue, 100e18, 100e18 * 10 / BPS);
    }

    function testMigrateAllUserFunds() external {
        // Pull funds from current vault and flush to the transfer adapter
        hevm.startPrank(governance);
        (uint256 withdrawnAmount, ) = alchemistV1USD.recallAll(1);
        alchemistV1USD.migrate(transferAdapter);
        uint256 flushed = alchemistV1USD.flush();
        hevm.stopPrank();
        // Contract may have previous balance so check if flushed is greater than or equal to withdrawn amount
        assertGt(flushed, withdrawnAmount - 1);

        // Pause the transmuter
        hevm.prank(governance);
        pausableTransmuterConduit.pauseTransmuter(true);
        // Stop V1 from minting more alUSD
        hevm.prank(treasury);
        alchemicToken.setWhitelist(alchemistV1USDAddress, false);
        // Pause the alchemist.
        hevm.prank(governance);
        alchemistV1USD.setEmergencyExit(true);
        hevm.stopPrank();

        // Roll chain ahead
        hevm.roll(block.number + 10);

        // List of addresses from V1
        V1AddressList V1List = new V1AddressList();
        address[2654] memory addresses = V1List.getAddresses();

        // Loop until all addresses have migrated
        for (uint i = 0; i < addresses.length; i++) {
            // Original debt/position from V1
            uint256 V1Debt = alchemistV1USD.getCdpTotalDebt(addresses[i]);
            uint256 V1Deposited = alchemistV1USD.getCdpTotalDeposited(addresses[i]);
            // Orignal debt/position from V2 which is used to calculate the difference
            // This accounts for users migrating already having positions in V2
            (int256 V2DebtBefore, ) = alchemistV2USD.accounts(addresses[i]);
            (uint256 V2SharesBefore, ) = alchemistV2USD.positions(addresses[i], yvDAI);

            // Users with less than 10 wei can possibly cause undercollateralized error
            if(V1Deposited < 10) {
                continue;
            }

            // User withdraws 
            hevm.prank(addresses[i], addresses[i]);
            alchemistV1USD.withdraw(1);
            (int256 V2DebtAfter, ) = alchemistV2USD.accounts(addresses[i]);

            int256 debtIncrease = V2DebtAfter - V2DebtBefore;

            // Users with 2:1 collaterlization ratio have debt reduced by 1000000 wei
            if(V1Debt > 0 && V1Deposited / V1Debt == 2) {
                assertEq(int256(V1Debt) - 1000000, debtIncrease);
            } else {
                assertEq(int256(V1Debt), debtIncrease);
            }

            // Verify underlying value of position in V2 within 2% of original
            (uint256 V2SharesAfter, ) = alchemistV2USD.positions(addresses[i], yvDAI);
            uint256 sharesDiff = V2SharesAfter - V2SharesBefore;
            uint256 underlyingValue = (sharesDiff * alchemistV2USD.getUnderlyingTokensPerShare(yvDAI) / scalar);
            assertApproxEq(underlyingValue, V1Deposited, V1Deposited * 10 / BPS);
        }

        // Hopefully the contract is completely drained or at least almost.
        assertEq(IERC20(DAI).balanceOf(address(transferAdapter)), 0);
    }
}