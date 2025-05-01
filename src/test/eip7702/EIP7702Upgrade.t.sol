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
import { IERC20Mintable, IERC20 } from "../../interfaces/IERC20Mintable.sol";
import { ITokenAdapter } from "../../interfaces/ITokenAdapter.sol";
import { IAlchemistV2AdminActions } from "../../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import { IAlchemistV2 } from "../../interfaces/IAlchemistV2.sol";  
import {ITestYieldToken} from "../../interfaces/test/ITestYieldToken.sol";
import {SafeERC20} from "../../libraries/SafeERC20.sol";
import {ECDSA} from "../../../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "../../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol"; 
import {ProxyAdmin} from "../../../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {AlchemistV2PreUpgrade} from "./AlchemistV2PreUpgrade.sol";
import "../../../lib/forge-std/src/Test.sol";


contract MockAlchemicTokenV2 is AlchemicTokenV2 {
    constructor(string memory _name, string memory _symbol, uint256 _flashFee) AlchemicTokenV2(_name, _symbol, _flashFee) {}

    function burn(address owner, uint256 amount) public {
       uint256 newAllowance = allowance(owner, msg.sender) - amount;
        _approve(owner, msg.sender, newAllowance);
        _burn(owner, amount);    }
}

contract EIP7702Upgrade is Test {

    // AlchemistV2

    // ----- [SETUP] Variables for setting up a minimal CDP -----

	// Callable contract variables
	TransmuterV2 transmuter;
	TransmuterBuffer transmuterBuffer;

    // // Proxy variables
    TransparentUpgradeableProxy proxyAlchemist;
    TransparentUpgradeableProxy proxyTransmuter;
    TransparentUpgradeableProxy proxyTransmuterBuffer;

    // // Contract variables
    // CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    AlchemistV2PreUpgrade alchemist;
    AlchemistV2PreUpgrade alchemistLogic;
    TransmuterV2 transmuterLogic;
    TransmuterBuffer transmuterBufferLogic;
    MockAlchemicTokenV2 alToken;
    TestYieldTokenAdapter tokenAdapter;
    Whitelist whitelist;
    ProxyAdmin proxyAdmin;

    // Token addresses
    address fakeUnderlyingToken;
    address fakeYieldToken;

    // Total minted debt
    uint256 public minted;

    // Total debt burned
    uint256 public burned;

    // Total tokens sent to transmuter
    uint256 public sentToTransmuter;

    // Parameters for AlchemicTokenV2
    string public _name;
    string public _symbol;
    uint256 public _flashFee;
    address public alOwner;

    mapping(address => bool) users;
    // ----- Variables for deposits & withdrawals -----

    // account funds to make deposits/test with
    uint256 accountFunds = 20_000_000e18;

    // amount of yield/underlying token to deposit
    uint256 depositAmount = 100_000e18;

    // random EOA for testing
    address externalUser = address(100);
    // another random EOA for testing
    address externalUser2 = address(200);

    // Storage slot where the implementation address is stored in EIP-1967 proxies
    // keccak256("eip1967.proxy.implementation") - 1
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function deployAlchemixV2Contracts() public {

        // Generate a new private key and address
        uint256 adminAddressPK = uint256(keccak256(abi.encodePacked("masterAddress", block.timestamp)));
        address masterAddress = vm.addr(adminAddressPK);
        // test maniplulation for convenience
        address caller = address(0xdead);
        address proxyOwner = masterAddress;
        vm.assume(caller != address(0));
        vm.assume(proxyOwner != address(0));
        vm.assume(caller != proxyOwner);
        vm.startPrank(caller);


        // Fake tokens
        TestERC20 testToken = new TestERC20(0, 18);
        fakeUnderlyingToken = address(testToken);
        TestYieldToken testYieldToken = new TestYieldToken(fakeUnderlyingToken);
        fakeYieldToken = address(testYieldToken);

        // Contracts and logic contracts
        alOwner = caller;
        alToken = new MockAlchemicTokenV2(_name, _symbol, _flashFee);
        tokenAdapter = new TestYieldTokenAdapter(fakeYieldToken);
        transmuterBufferLogic = new TransmuterBuffer();
        transmuterLogic = new TransmuterV2();
        alchemistLogic = new AlchemistV2PreUpgrade();
        whitelist = new Whitelist();

        // Proxy contracts
        // TransmuterBuffer proxy
        bytes memory transBufParams = abi.encodeWithSelector(TransmuterBuffer.initialize.selector, alOwner, address(alToken));

        proxyTransmuterBuffer = new TransparentUpgradeableProxy(address(transmuterBufferLogic), proxyOwner, transBufParams);

        transmuterBuffer = TransmuterBuffer(address(proxyTransmuterBuffer));

        // TransmuterV2 proxy
        bytes memory transParams =
            abi.encodeWithSelector(TransmuterV2.initialize.selector, address(alToken), fakeUnderlyingToken, address(transmuterBuffer), whitelist);

        proxyTransmuter = new TransparentUpgradeableProxy(address(transmuterLogic), proxyOwner, transParams);
        transmuter = TransmuterV2(address(proxyTransmuter));


		// AlchemistV2 proxy
		IAlchemistV2AdminActions.InitializationParams memory params = IAlchemistV2AdminActions.InitializationParams({
			admin: alOwner,
			debtToken: address(alToken),
			transmuter: address(transmuterBuffer),
			minimumCollateralization: 2 * 1e18,
			protocolFee: 1000,
			protocolFeeReceiver: address(10),
			mintingLimitMinimum: 1,
			mintingLimitMaximum: uint256(type(uint160).max),
			mintingLimitBlocks: 300,
			whitelist: address(whitelist)
		});

        bytes memory alchemParams = abi.encodeWithSelector(AlchemistV2PreUpgrade.initialize.selector, params);
        proxyAdmin = new ProxyAdmin();
        proxyAlchemist = new TransparentUpgradeableProxy(address(alchemistLogic), address(proxyAdmin), alchemParams);
        alchemist = AlchemistV2PreUpgrade(address(proxyAlchemist));

        // Whitelist alchemist proxy for minting tokens
        alToken.setWhitelist(address(proxyAlchemist), true);

        // Create token adapter configs for both yeild and underlying tokens
        // Must add underlying  config before yeild token

        IAlchemistV2AdminActions.UnderlyingTokenConfig memory underlyingTokenConfig = IAlchemistV2AdminActions.UnderlyingTokenConfig({
            repayLimitMinimum: 1,
            repayLimitMaximum: 1000,
            repayLimitBlocks: 10,
            liquidationLimitMinimum: 1,
            liquidationLimitMaximum: 1000,
            liquidationLimitBlocks: 7200
        });

        alchemist.addUnderlyingToken(address(fakeUnderlyingToken), underlyingTokenConfig);

        IAlchemistV2AdminActions.YieldTokenConfig memory yieldTokenConfig =
            IAlchemistV2AdminActions.YieldTokenConfig({adapter: address(tokenAdapter), maximumLoss: 1, maximumExpectedValue: 1e50, creditUnlockBlocks: 1});

        alchemist.addYieldToken(address(fakeYieldToken), yieldTokenConfig);

        // Enable token adapters for both yeild and underlying tokens
        alchemist.setYieldTokenEnabled(address(fakeYieldToken), true);
        alchemist.setUnderlyingTokenEnabled(address(fakeUnderlyingToken), true);

        // Skipping all transmuter interaction until transmuter v2 is implemented

        // Set the alchemist for the transmuterBuffer
        transmuterBuffer.setAlchemist(address(proxyAlchemist));
        // Set the transmuter buffer's transmuter
        transmuterBuffer.setTransmuter(fakeUnderlyingToken, address(transmuter));
        // Set alOwner as a keeper
        alchemist.setKeeper(alOwner, true);
        // Set flow rate for transmuter buffer
        transmuterBuffer.setFlowRate(fakeUnderlyingToken, 325e18);
        whitelist.add(externalUser);
        whitelist.add(externalUser2);

        vm.stopPrank();

        // Add funds to test accounts
        deal(address(fakeUnderlyingToken), address(fakeYieldToken), 1_000_000_000e18);
        deal(address(fakeYieldToken), externalUser, accountFunds);
        deal(address(fakeYieldToken), externalUser2, accountFunds);
        deal(address(fakeUnderlyingToken), externalUser, accountFunds);
        deal(address(fakeUnderlyingToken), externalUser2, accountFunds);
        deal(address(alToken), externalUser, accountFunds/2);
        deal(address(alToken), externalUser2, accountFunds/2);

        vm.startPrank(externalUser);
        SafeERC20.safeApprove(address(fakeUnderlyingToken), address(fakeYieldToken), accountFunds);

        // faking initial alchemist supply
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), 10_000_000e18);
        alchemist.deposit(address(fakeYieldToken), 10_000_000e18, externalUser);
        vm.stopPrank();
    }

    function setupUserAccounts() internal {
        uint256 initialDeposit = 10_000e18;
        uint256 mintAmount = initialDeposit/2;
        // User 1 deposit and mint
        vm.startPrank(externalUser);
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), initialDeposit);
        alchemist.deposit(address(fakeYieldToken), initialDeposit, externalUser);
        alchemist.mint(mintAmount, externalUser);
        vm.stopPrank();
        
        // User 2 deposit only
        vm.startPrank(externalUser2);
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), initialDeposit);
        alchemist.deposit(address(fakeYieldToken), initialDeposit, externalUser2);
        vm.stopPrank();
    }

    function setUp() public {
        // Deploy the Alchemix V2 contract
        deployAlchemixV2Contracts();
        setupUserAccounts();
    }

    // Store data in structs to avoid stack too deep
    struct UserPositionData {
        int256 debt;
        uint256 shares;
        uint256 weight;
        uint256 tokenCount;
    }

    function testAccountAfterUpgrade() public {
        // 1. Capture positions before upgrade
        UserPositionData memory user1Before = captureUserPosition(externalUser);
        UserPositionData memory user2Before = captureUserPosition(externalUser2);
        
        // 2. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 3. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();

        // 4. Verify positions after upgrade
        UserPositionData memory user1After = captureUserPosition(externalUser);
        UserPositionData memory user2After = captureUserPosition(externalUser2);
        
        // 5. Assert state preservation
        assertUserPositionUnchanged(user1Before, user1After, "User 1");
        assertUserPositionUnchanged(user2Before, user2After, "User 2");
    }

    function testWithdrawalUnderlyingAfterUpgrade() public {        
         // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        // 3. Verify functionality continues to work post-upgrade
        vm.startPrank(externalUser);
        // balance before
        uint256 balanceBefore = IERC20(address(fakeUnderlyingToken)).balanceOf(externalUser);
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), accountFunds);
        alchemist.withdrawUnderlying(address(fakeYieldToken), 100, externalUser, 0);
        // balance after
        uint256 balanceAfter = IERC20(address(fakeUnderlyingToken)).balanceOf(externalUser);
        assertGt(balanceAfter, balanceBefore, "Underlying token balance not increased after withdrawal");
        vm.stopPrank();
    }

    function testWithdrawfterUpgrade() public {        
        // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        // 3. Verify functionality continues to work post-upgrade
        vm.startPrank(externalUser);
        // balance before
        uint256 balanceBefore = IERC20(address(fakeYieldToken)).balanceOf(externalUser);
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), accountFunds);
        alchemist.withdraw(address(fakeYieldToken), 100, externalUser);
        // balance after
        uint256 balanceAfter = IERC20(address(fakeYieldToken)).balanceOf(externalUser);
        assertGt(balanceAfter, balanceBefore, "Underlying token balance not increased after withdrawal");
        vm.stopPrank();
    }

    function testMintAfterUpgrade() public {        
        // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        // 3. Verify functionality continues to work post-upgrade
        vm.startPrank(externalUser);
        // balance before
        uint256 balanceBefore = IERC20(address(alToken)).balanceOf(externalUser);
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), accountFunds);
        alchemist.mint(1000e18, externalUser);
        // balance after
        uint256 balanceAfter = IERC20(address(alToken)).balanceOf(externalUser);
        assertGt(balanceAfter, balanceBefore, "alToken balance not increased after minting");
        vm.stopPrank();
    }

    function testDepositAfterUpgrade() public {        
          // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        // 3. Verify functionality continues to work post-upgrade
        vm.startPrank(externalUser);
        // get position before
        (uint256 sharesBefore, ) = alchemist.positions(externalUser, address(fakeYieldToken));
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), accountFunds);
        alchemist.deposit(address(fakeYieldToken), 1000e18, externalUser);
        // get position after
        (uint256 sharesAfter, ) = alchemist.positions(externalUser, address(fakeYieldToken));
        assertGt(sharesAfter, sharesBefore, "Position shares not increased after deposit");
        vm.stopPrank();
    }

    function testRepayAfterUpgrade() public {        
        // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        
        // First ensure user has some debt
        vm.startPrank(externalUser);
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), accountFunds);
        alchemist.mint(1000e18, externalUser);
        vm.stopPrank();
        
        // 2. Verify repay functionality works post-upgrade
        vm.startPrank(externalUser);
        // debt before
        (int256 debtBefore, ) = alchemist.accounts(externalUser);
        SafeERC20.safeApprove(address(fakeUnderlyingToken), address(alchemist), accountFunds);
        alchemist.repay(address(fakeUnderlyingToken), 100, externalUser);
        // debt after
        (int256 debtAfter, ) = alchemist.accounts(externalUser);
        assertLt(debtAfter, debtBefore, "Debt not decreased after repayment");
        vm.stopPrank();
    }

    function testDonateAfterUpgrade() public {        
        // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        // 3. Verify donate functionality works post-upgrade
        vm.startPrank(externalUser);
        // capture weight before
        (, uint256 weightBefore) = alchemist.positions(externalUser, address(fakeYieldToken));
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), accountFunds);
        alToken.approve(address(alchemist), 1000e18);
        alchemist.mint(1000e18, externalUser);
        alchemist.donate(address(fakeYieldToken), 100e18);
        // capture weight after
        (, uint256 weightAfter) = alchemist.positions(externalUser, address(fakeYieldToken));
        assertGe(weightAfter, weightBefore, "Position weight did not increase after donation");
        vm.stopPrank();
    }

    function testBurnAfterUpgrade() public {        
        // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        
        // First ensure user has some debt
        vm.startPrank(externalUser);
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), accountFunds);
        alchemist.mint(1000e18, externalUser);
        vm.stopPrank();
        
        // 3. Verify burn functionality works post-upgrade
        vm.startPrank(externalUser);
        // debt before
        (int256 debtBefore, ) = alchemist.accounts(externalUser);
        alToken.approve(address(alchemist), accountFunds);
        alchemist.burn(100e18, externalUser);
        // debt after
        (int256 debtAfter, ) = alchemist.accounts(externalUser);
        assertLt(debtAfter, debtBefore, "Debt not decreased after burning");
        vm.stopPrank();
    }

    function testImplementationSlotUpdate() public {

        // 1. Get the current implementation address from the proxy's storage
        address implementationAddressBefore = getImplementationFromSlot();
        
        // 2. Verify it matches our original implementation
        assertEq(implementationAddressBefore, address(alchemistLogic), "Initial implementation address mismatch");
        
        // 3. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 4. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        // 5. Get the implementation address from storage slot after upgrade
        address implementationAddressAfter = getImplementationFromSlot();
        
        // 6. Verify the storage slot has been updated to point to the new implementation
        assertEq(implementationAddressAfter, address(updatedAlchemist), "Implementation slot not updated correctly");
        
        console2.log("Original implementation:", implementationAddressBefore);
        console2.log("New implementation:", implementationAddressAfter);
    }

    function testDepositUnderlyingAfterUpgrade() public {        
         // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        // 3. Verify functionality continues to work post-upgrade
        vm.startPrank(externalUser);
        // get position before
        (uint256 sharesBefore, ) = alchemist.positions(externalUser, address(fakeYieldToken));
        SafeERC20.safeApprove(address(fakeUnderlyingToken), address(alchemist), accountFunds);
        alchemist.depositUnderlying(address(fakeYieldToken), 1000e18, externalUser, 0);
        // get position after
        (uint256 sharesAfter, ) = alchemist.positions(externalUser, address(fakeYieldToken));
        assertGt(sharesAfter, sharesBefore, "Position shares not increased after underlying deposit");
        vm.stopPrank();
    }

    function testWithdrawFromAfterUpgrade() public {        
        // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        
        // First set up withdrawal approval from externalUser to externalUser2
        vm.startPrank(externalUser);
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), accountFunds);
        alchemist.approveWithdraw(externalUser2, address(fakeYieldToken), type(uint256).max);
        vm.stopPrank();
        
        // Check balances before withdrawal
        uint256 user2BalanceBefore = IERC20(address(fakeYieldToken)).balanceOf(externalUser2);
        (uint256 user1SharesBefore, ) = alchemist.positions(externalUser, address(fakeYieldToken));
        
        // 2. Verify withdrawFrom functionality works post-upgrade
        vm.startPrank(externalUser2);
        alchemist.withdrawFrom(externalUser, address(fakeYieldToken), 100, externalUser2);
        vm.stopPrank();
        
        // Verify user2's balance increased and user1's shares decreased
        uint256 user2BalanceAfter = IERC20(address(fakeYieldToken)).balanceOf(externalUser2);
        (uint256 user1SharesAfter, ) = alchemist.positions(externalUser, address(fakeYieldToken));
        
        assertGt(user2BalanceAfter, user2BalanceBefore, "Receiver balance not increased after withdrawFrom");
        assertLt(user1SharesAfter, user1SharesBefore, "Source shares not decreased after withdrawFrom");
    }

    function testMintFromAfterUpgrade() public {        
        // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
        
        // First set up minting approval from externalUser to externalUser2
        vm.startPrank(externalUser);
        SafeERC20.safeApprove(address(fakeYieldToken), address(alchemist), accountFunds);
        alchemist.approveMint(externalUser2, type(uint256).max);
        vm.stopPrank();
        
        // Check balances before minting
        uint256 user2BalanceBefore = IERC20(address(alToken)).balanceOf(externalUser2);
        (int256 user1DebtBefore, ) = alchemist.accounts(externalUser);
        
        // 2. Verify mintFrom functionality works post-upgrade
        vm.startPrank(externalUser2);
        alchemist.mintFrom(externalUser, 1000e18, externalUser2);
        vm.stopPrank();
        
        // Verify user2's balance increased and user1's debt increased
        uint256 user2BalanceAfter = IERC20(address(alToken)).balanceOf(externalUser2);
        (int256 user1DebtAfter, ) = alchemist.accounts(externalUser);
        
        assertGt(user2BalanceAfter, user2BalanceBefore, "Receiver balance not increased after mintFrom");
        assertGt(user1DebtAfter, user1DebtBefore, "Source debt not increased after mintFrom");
    }

    function doUpgradeHelper() public {
        // 1. Deploy new implementation
        AlchemistV2 updatedAlchemist = new AlchemistV2();

        address admin = proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(proxyAlchemist))); 
        address owner = proxyAdmin.owner();

        // 2. Perform upgrade
        vm.startPrank(owner);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(proxyAlchemist)), address(updatedAlchemist));
        vm.stopPrank();
    }

    // Helper function to capture user position data
    function captureUserPosition(address user) internal view returns (UserPositionData memory data) {
        (int256 debt, address[] memory tokens) = alchemist.accounts(user);
        (uint256 shares, uint256 weight) = alchemist.positions(user, address(fakeYieldToken));
        
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
        bytes32 implementationBytes = vm.load(address(proxyAlchemist), IMPLEMENTATION_SLOT);
        return address(uint160(uint256(implementationBytes)));
    }

}