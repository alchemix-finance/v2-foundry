// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";

import {AlchemistV2} from "../AlchemistV2.sol";
import {TransferAdapter} from "../adapters/V1/TransferAdapter.sol";

import {IAlchemistV1} from "../interfaces/IAlchemistV1.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {ITransmuterV1} from "../interfaces/ITransmuterV1.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract V2MigrationTest is DSTestPlus, stdCheats {
    uint256 constant BPS = 10000;
    address constant alchemistV1USDAddress = 0xc21D353FF4ee73C572425697f4F5aaD2109fe35b;
    address constant alchemistV2USDAddress = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant alUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant governance = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant transmuterV1Address = 0x4ac2377ed3ee376Ff07d706BEaBC2Fa38ecfB41C;
    address constant whitelistV2Address = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    address constant whitelistV2Owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant yvDAI = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;

    IAlchemistV1 alchemistV1USD = IAlchemistV1(alchemistV1USDAddress);
    IAlchemistV2 alchemistV2USD = IAlchemistV2(alchemistV2USDAddress);
    ITransmuterV1 transmuterV1 = ITransmuterV1(transmuterV1Address);
    IWhitelist whitelistV2 = IWhitelist(whitelistV2Address);

    TransferAdapter transferAdapter;

    function setUp() external {
        transferAdapter = new TransferAdapter(alchemistV1USDAddress, alUSD, DAI, yvDAI, alchemistV1USDAddress, alchemistV2USDAddress);

        // Allow adapter to deposit underlying tokens into V2
        hevm.prank(whitelistV2Owner);
        whitelistV2.add(address(transferAdapter));

        // Start a position in V1 as 0xbeef and go into debt
        hevm.startPrank(address(0xbeef), address(0xbeef));
        tip(DAI, address(0xbeef), 100e18);
        SafeERC20.safeApprove(DAI, alchemistV1USDAddress, 100e18);
        alchemistV1USD.deposit(100e18);
        // Mint throws 'unhealthy collateralizatiob ratio'
        //alchemistV1USD.mint(40e18);
        // Approve adapter to mint on behalf of user
        alchemistV2USD.approveMint(address(transferAdapter), 40e18);
        hevm.stopPrank();
    }

    function testMigrateFunds() external {
        // V1 debt before migration
        uint256 originalDebt = alchemistV1USD.getCdpTotalDebt(address(0xbeef));

        // Pull funds from current vault and flush to the transfer adapter
        hevm.startPrank(governance);
        // recallAll not working BentoboxV1 cant transfer enough DAI. Using specified amt for now
        // (uint256 withdrawnAmount, ) = alchemistV1USD.recallAll(1);
        (uint256 withdrawnAmount, ) = alchemistV1USD.recall(1, 1000e18);
        alchemistV1USD.migrate(transferAdapter);
        uint256 flushed = alchemistV1USD.flush();
        hevm.stopPrank();
        // Contract may have previous balance so check if flushed is greater than or equal to withdrawn amount
        assertGt(flushed, withdrawnAmount - 1);
        assertEq(transferAdapter.totalValue(), flushed);

        // TODO Pause the transmuter. Stop V1 from minting more alUSD. Pause the alchemist.
        // TODO Test that only withdraw works after these steps.

        // Roll chain ahead
        hevm.roll(block.number + 10);

        // User withdraws 
        hevm.startPrank(address(0xbeef), address(0xbeef));
        alchemistV1USD.withdraw(1);

        // TODO add test that expects revert from withdrawing more than 1

        // Debts must be the same as debt in V1
        (int256 V2Debt, ) = alchemistV2USD.accounts(address(0xbeef));
        assertEq(int256(originalDebt), V2Debt);
    }
}
