// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13 <0.9.0;
import {Test, console2} from "../../../lib/forge-std/src/Test.sol"; 
import {VmSafe} from "../../../lib/forge-std/src/Vm.sol";
import {BatchCallAndSponsor} from "../mocks/BatchCallAndSponsor.sol";
import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { CheatCodes } from "../../test/utils/Cheatcodes.sol";
import { AlchemistV2 } from "../../AlchemistV2.sol";
import { AlchemicTokenV2 } from "../../AlchemicTokenV2.sol";
import { TransmuterV2 } from "../../TransmuterV2.sol";
import { TransmuterBuffer } from "../../TransmuterBuffer.sol";
import { Whitelist } from "../../utils/Whitelist.sol";
import { TestERC20 } from "../../test/mocks/TestERC20.sol";
import { TestYieldToken } from "../../test/mocks/TestYieldToken.sol";
import { TestYieldTokenAdapter } from "../../test/mocks/TestYieldTokenAdapter.sol";
import { IERC20Mintable } from "../../interfaces/IERC20Mintable.sol";
import { ITokenAdapter } from "../../interfaces/ITokenAdapter.sol";
import { IAlchemistV2AdminActions } from "../../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import { IAlchemistV2 } from "../../interfaces/IAlchemistV2.sol";  
import {ITestYieldToken} from "../../interfaces/test/ITestYieldToken.sol";
import {SafeERC20} from "../../libraries/SafeERC20.sol";
import {ECDSA} from "../../../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "../../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol"; 
import {ProxyAdmin} from "../../../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {AlchemistV2PreUpgrade} from "./AlchemistV2PreUpgrade.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../../lib/forge-std/src/Test.sol";

/**
 * @dev Minimal interface for ProxyAdmin that only includes the upgrade function.
 */
interface IProxyAdmin {
    /**
     * @dev Upgrades `proxy` to `implementation`. See {TransparentUpgradeableProxy-upgradeTo}.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function upgrade(ITransparentUpgradeableProxy proxy, address implementation) external;

    /**
     * @dev Returns the current admin of `proxy`.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function getProxyAdmin(ITransparentUpgradeableProxy proxy) external view returns (address);


    /**
     * @dev Returns the address of the current owner.
     */
    function owner() external view returns (address);
}


// fork block 22385265
contract EIP7702UpgradeIntegrationTest is Test {
    // The contract that the user will delegate execution to.
    BatchCallAndSponsor public implementation;
    // AlchemistV2
	// Callable contract variables
	IAlchemistV2 alchemist;
	TransmuterV2 transmuter;
	TransmuterBuffer transmuterBuffer;

    // // MAINNET variables
    TransparentUpgradeableProxy proxyAlchemist;
    address PROXY_ALCHEMIST_ADDRESS = address(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd);
    address PROXY_ADMIN_ADDRESS = address(0xE0fC5CB7665041CdA26969A2D1ceb5cD5046347d);
    address PROXY_WHITELIST_ADDRESS = address(0x78537a6CeBa16f412E123a90472C6E0e9A8F1132);
    address YIELD_TOKEN = address(0xdA816459F1AB5631232FE5e97a05BBBb94970c95);
    address ALCHEMIST_V2_ADDRESS = address(0x855EB163415A57Bd52E25882E9C449885Fa01f47);
    address AL_TOKEN_ADDRESS = address(0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9);
    //Contract variables
    Whitelist whitelist;
    // ProxyAdmin proxyAdmin;
    IProxyAdmin proxyAdmin;
    mapping(address => bool) users;
    // ----- Variables for deposits & withdrawals ----- //
    // real EOA for testing
    address user1 = address(0xcB971a5457cff604970af12fAf0aEc6DC6C36281);
    // real EOA for testing
    address user2 = address(0x6800212FeF0f1729B96210e3Fdadf50FC21cF4e0);
    // real EOA for testing
    address user3 = address(0x2a6bf8a714AcDbe9d6e9dd1753Ca09b8e7D95328);
    // real EOA for testing
    address user4 = address(0x3382A350C1e1Db5c306E10B4D750BF4668c12c65);

    // Storage slot where the implementation address is stored in EIP-1967 proxies
    // keccak256("eip1967.proxy.implementation") - 1
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Store data in structs to avoid stack too deep
    struct UserPositionData {
        int256 debt;
        uint256 shares;
        uint256 weight;
        uint256 tokenCount;
    }

    function setUp() public {
         alchemist =  IAlchemistV2(PROXY_ALCHEMIST_ADDRESS);
         whitelist = Whitelist(PROXY_WHITELIST_ADDRESS);
    }

    function testAccountActionsAfterUpgrade() public {
        // 1. Capture positions before upgrade
        UserPositionData memory user1Before = captureUserPosition(user1);
        UserPositionData memory user2Before = captureUserPosition(user2);
        UserPositionData memory user3Before = captureUserPosition(user3);
        UserPositionData memory user4Before = captureUserPosition(user4);
        
        // 2. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();
        proxyAdmin = IProxyAdmin(PROXY_ADMIN_ADDRESS);
        address owner = proxyAdmin.owner();

        // 3. Perform upgrade
        vm.startPrank(owner);
        whitelist.add(user1);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(PROXY_ALCHEMIST_ADDRESS), address(updatedAlchemist));
        vm.stopPrank();
        
        // 4. Verify positions after upgrade
        UserPositionData memory user1After = captureUserPosition(user1);
        UserPositionData memory user2After = captureUserPosition(user2);
        UserPositionData memory user3After = captureUserPosition(user3);
        UserPositionData memory user4After = captureUserPosition(user4);
        // 5. Assert state preservation
        assertUserPositionUnchanged(user1Before, user1After, "User 1");
        assertUserPositionUnchanged(user2Before, user2After, "User 2");
        assertUserPositionUnchanged(user3Before, user3After, "User 3");
        assertUserPositionUnchanged(user4Before, user4After, "User 4");
        
        // 6. Verify functionality continues to work post-upgrade
        vm.startPrank(user1);
        uint256 alTokenBalanceBefore = IERC20(AL_TOKEN_ADDRESS).balanceOf(user1);
        alchemist.mint(100e18, user1); // Should still be able to mint
        uint256 alTokenBalanceAfter = IERC20(AL_TOKEN_ADDRESS).balanceOf(user1);
        assertGt(alTokenBalanceAfter, alTokenBalanceBefore, "User 1 should have received AL tokens after minting");
        vm.stopPrank();
    }

    function testImplementationSlotUpdate() public {

        // 1. Get the current implementation address from the proxy's storage
        address implementationAddressBefore = getImplementationFromSlot();
        
        // 2. Verify it matches our original implementation
        assertEq(implementationAddressBefore, ALCHEMIST_V2_ADDRESS, "Initial implementation address mismatch");
        
        // 3. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        proxyAdmin = IProxyAdmin(PROXY_ADMIN_ADDRESS);
        address owner = proxyAdmin.owner();

        // 4. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(PROXY_ALCHEMIST_ADDRESS), address(updatedAlchemist));
        vm.stopPrank();
        // 5. Get the implementation address from storage slot after upgrade
        address implementationAddressAfter = getImplementationFromSlot();
        
        // 6. Verify the storage slot has been updated to point to the new implementation
        assertEq(implementationAddressAfter, address(updatedAlchemist), "Implementation slot not updated correctly");
        
        console2.log("Original implementation:", implementationAddressBefore);
        console2.log("New implementation:", implementationAddressAfter);
    }

    // Helper function to capture user position data
    function captureUserPosition(address user) internal view returns (UserPositionData memory data) {
        (int256 debt, address[] memory tokens) = alchemist.accounts(user);
        (uint256 shares, uint256 weight) = alchemist.positions(user, YIELD_TOKEN);
        
        data.debt = debt;
        data.shares = shares;
        data.weight = weight;
        data.tokenCount = tokens.length;
        
        return data;
    }

    // Helper function to verify user position unchanged
    function assertUserPositionUnchanged(
        UserPositionData memory beforeUpgrade,
        UserPositionData memory afterUpgrade,
        string memory userLabel
    ) internal {
        assertEq(beforeUpgrade.debt, afterUpgrade.debt, string.concat(userLabel, " debt changed after upgrade"));
        assertEq(beforeUpgrade.tokenCount, afterUpgrade.tokenCount, string.concat(userLabel, " token count changed"));
        assertEq(beforeUpgrade.shares, afterUpgrade.shares, string.concat(userLabel, " shares changed after upgrade"));
        assertEq(beforeUpgrade.weight, afterUpgrade.weight, string.concat(userLabel, " accrued weight changed after upgrade"));
    }

    // Helper function to read the implementation address directly from storage
    function getImplementationFromSlot() internal view returns (address) {
        // Use vm.load to read storage from the proxy contract at the implementation slot
        bytes32 implementationBytes = vm.load(PROXY_ALCHEMIST_ADDRESS, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(implementationBytes)));
    }

}