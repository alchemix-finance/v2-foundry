// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13 <0.9.0;
import {Test, console2} from "../../../lib/forge-std/src/Test.sol"; 
import {VmSafe} from "../../../lib/forge-std/src/Vm.sol";
import {BatchCallAndSponsor} from "../mocks/BatchCallAndSponsor.sol";
import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { CheatCodes } from "../../test/utils/Cheatcodes.sol";
import "../../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol"; 
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
import "../../../lib/forge-std/src/Test.sol";
import {ITestYieldToken} from "../../interfaces/test/ITestYieldToken.sol";
import {SafeERC20} from "../../libraries/SafeERC20.sol";
import {ECDSA} from "../../../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    AAVETokenAdapter,
    InitializationParams as AdapterInitializationParams
} from "../../adapters/aave/AAVETokenAdapter.sol";

import {StaticAToken} from "../../external/aave/StaticAToken.sol";
import {ILendingPool} from "../../interfaces/external/aave/ILendingPool.sol";
import {ITokenGateway} from "../../interfaces/ITokenGateway.sol";
import {ATokenGateway} from "../../adapters/aave/ATokenGateway.sol";
import {YTokenGateway} from "../../adapters/yearn/YTokenGateway.sol";
import {WETHGateway} from "../../WETHGateway.sol";
import {AutoleverageCurveMetapool} from "../../AutoleverageCurveMetapool.sol";
import {AutoleverageCurveFactoryethpool} from "../../AutoleverageCurveFactoryethpool.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract EIP7702Periphery is Test {
    // The contract that the user will delegate execution to.
    BatchCallAndSponsor public implementation;

    // ERC-20 token contract for minting test tokens.
    MockERC20 public token;

    // AlchemistV2

    // ----- [SETUP] Variables for setting up a minimal CDP -----

	// Callable contract variables
	AlchemistV2 alchemist;
	TransmuterV2 transmuter;
	TransmuterBuffer transmuterBuffer;

    // // Proxy variables
    TransparentUpgradeableProxy proxyAlchemist;
    TransparentUpgradeableProxy proxyTransmuter;
    TransparentUpgradeableProxy proxyTransmuterBuffer;

    // // Contract variables
    // CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    AlchemistV2 alchemistLogic;
    TransmuterV2 transmuterLogic;
    TransmuterBuffer transmuterBufferLogic;
    AlchemicTokenV2 alToken;
    Whitelist whitelist;

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

    // LTV
    uint256 public LTV = 11e17; // 1.1, prev = 2 * 1e18

    
    // Periphery contracts
    TestYieldTokenAdapter tokenAdapter;
    ITokenGateway aTokenGateway;
    YTokenGateway yTokenGateway;
    WETHGateway wethGateway;
    AutoleverageCurveMetapool immutable metapoolHelper = new AutoleverageCurveMetapool();
    AutoleverageCurveFactoryethpool immutable factoryethpoolHelper = new AutoleverageCurveFactoryethpool();
    uint256 constant BPS = 10000;
    address constant weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9; // Sepolia WETH
    address constant dai = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357; //  Sepolia AAVE V3 DAI
    address constant aToken = 0x29598b72eb5CeBd806C5dCD549490FdA35B13cD8;  // Sepolia AAVE V3 aDAI 
    ILendingPool lendingPool = ILendingPool(0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951); // Sepolia Aave V3 Lending Pool
    uint256 constant TEST_COLLATERAL_INITIAL = 1_000_000 ether;
    uint256 constant TEST_COLLATERAL_TOTAL = 1_990_000 ether;
    uint256 constant TEST_SLIPPAGE_MULTIPLIER = 10050; // out of 10000
    string wrappedTokenName = "staticAaveDai";
    string wrappedTokenSymbol = "saDAI";
    StaticAToken staticAToken;
    address metapool = 0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c; // alUSD-3CRV metapool
    int128 metapoolI = 0; // alUSD index
    int128 metapoolJ = 1; // DAI index
    address factorypool = 0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e; // alETH-ETH factoryethpool
    int128 factorypoolI = 1; // alETH index
    int128 factorypoolJ = 0; // ETH index
    event CallExecuted(address indexed to, uint256 value, bytes data);
    event BatchExecuted(uint256 indexed nonce, BatchCallAndSponsor.Call[] calls);



    function deployAlchemixV2Contracts(address caller) public {

        // Generate a new private key and address
        uint256 adminAddressPK = uint256(keccak256(abi.encodePacked("masterAddress", block.timestamp)));
        address masterAddress = vm.addr(adminAddressPK);
        // test maniplulation for convenience
        address proxyOwner = masterAddress;
        vm.assume(caller != address(0));
        vm.assume(proxyOwner != address(0));
        vm.assume(caller != proxyOwner);

        // Fake tokens
        TestERC20 testToken = new TestERC20(0, 18);
        fakeUnderlyingToken = address(testToken);
        TestYieldToken testYieldToken = new TestYieldToken(fakeUnderlyingToken);
        fakeYieldToken = address(testYieldToken);

        // Contracts and logic contracts
        alOwner = caller;
        alToken = new AlchemicTokenV2(_name, _symbol, _flashFee);
        tokenAdapter = new TestYieldTokenAdapter(fakeYieldToken);
        transmuterBufferLogic = new TransmuterBuffer();
        transmuterLogic = new TransmuterV2();
        alchemistLogic = new AlchemistV2();
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

        bytes memory alchemParams = abi.encodeWithSelector(AlchemistV2.initialize.selector, params);
        proxyAlchemist = new TransparentUpgradeableProxy(address(alchemistLogic), proxyOwner, alchemParams);
        alchemist = AlchemistV2(address(proxyAlchemist));

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

    }

    function deployYTokenGateway() public {
        yTokenGateway = new YTokenGateway(address(whitelist), address(alchemist));
        whitelist.add(address(yTokenGateway));
    }

    function deployATokenGateway() public {
        aTokenGateway = new ATokenGateway(address(whitelist), address(alchemist));
        whitelist.add(address(aTokenGateway));
    }

    function deployWETHGateway() public {
        wethGateway = new WETHGateway(address(weth), address(whitelist));
        whitelist.add(address(wethGateway));
    }

    function setUpAutoLeverageBaseInheritedContracts() public {
        whitelist.add(address(metapoolHelper));
        whitelist.add(address(factoryethpoolHelper));
    }

    function setUp() public {
        address caller = address(0xdead);
        vm.startPrank(caller);
        // Deploy contracts
        deployAlchemixV2Contracts(caller);
        deployYTokenGateway();
        deployATokenGateway();
        deployWETHGateway();
        setUpAutoLeverageBaseInheritedContracts();
        // Deploy the delegation contract (the authorized address will delegate calls to this contract).
        implementation = new BatchCallAndSponsor();
        vm.stopPrank();
    }

    function testATokenGatewayDepositWithFreshAddressSponsoredTransaction() public {
        // Generate a new private key and address
        uint256 freshPKA = uint256(keccak256(abi.encodePacked("freshA", block.timestamp)));
        address payable freshAddressA = payable(vm.addr(freshPKA));
        
        console2.log("Fresh address A code length:", address(freshAddressA).code.length);
        
        uint256 amount = 1000e18;
        // Fund the fresh address
        deal(address(fakeYieldToken), freshAddressA, amount);        


         // Generate a new private key and address
        uint256 freshPKB = uint256(keccak256(abi.encodePacked("freshB", block.timestamp)));
        address freshAddressB = vm.addr(freshPKB);
        
        console2.log("Fresh address B code length:", address(freshAddressB).code.length);
        // Setup the call to the ATokenGateway deposit function
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](4); 
        // Then call deposit function on the ATokenGateway 
        calls[0] = BatchCallAndSponsor.Call({
            to: address(aTokenGateway),
            value: 0,
            data: abi.encodeCall(aTokenGateway.deposit, (address(fakeYieldToken), 100e18, freshAddressA))
        });
        
        bytes memory expectedRevert = abi.encodeWithSignature("Unauthorized(string)", "Not whitelisted");
        executeEIP7702Transaction(freshAddressA, freshPKA, freshPKB, calls, expectedRevert);
    }


    function testATokenGatewayWithdrawWithFreshAddressSponsoredTransaction() public {
        uint256 amount = 1000e18;

        // Generate a new private key and address
        uint256 freshPKA = uint256(keccak256(abi.encodePacked("freshA", block.timestamp, "withdraw")));
        address payable freshAddressA = payable(vm.addr(freshPKA));
        
        console2.log("Fresh address A code length:", address(freshAddressA).code.length);
        // Fund the fresh address with DAI
        deal(address(fakeYieldToken), freshAddressA, amount);
        
        // Generate a new private key and address for sponsor
        uint256 freshPKB = uint256(keccak256(abi.encodePacked("freshB", block.timestamp, "withdraw")));
        address freshAddressB = vm.addr(freshPKB);
        
        console2.log("Fresh address B code length:", address(freshAddressB).code.length);
        
        // Setup the call to the ATokenGateway withdraw function
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](2); 
        
        // Then call withdraw function on the ATokenGateway
        calls[0] = BatchCallAndSponsor.Call({
            to: address(aTokenGateway),
            value: 0,
            data: abi.encodeCall(aTokenGateway.withdraw, (address(fakeYieldToken), 100e18, freshAddressA))
        });
        
        bytes memory expectedRevert = abi.encodeWithSignature("Unauthorized(string)", "Not whitelisted");
        executeEIP7702Transaction(freshAddressA, freshPKA, freshPKB, calls, expectedRevert);
    } 


    /// Simplifying the setup of the next to highlight only the Smart Contract Access Control ///


    function testYTokenGatewayDepositSponsoredTransaction() public {
        uint256 amount = 1000e18;

        uint256 freshPKA = uint256(keccak256(abi.encodePacked("freshA", block.timestamp, "YTokenGatewayDeposit")));
        address payable freshAddressA = payable(vm.addr(freshPKA));
        
        // Fund with yield tokens
        deal(address(fakeYieldToken), freshAddressA, amount);
        
        uint256 freshPKB = uint256(keccak256(abi.encodePacked("freshB", block.timestamp, "YTokenGatewayDeposit")));
        
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](2);
        
        // Approve yield token
        calls[0] = BatchCallAndSponsor.Call({
            to: address(fakeYieldToken), 
            value: 0,
            data: abi.encodeCall(ERC20.approve, (address(yTokenGateway), amount))
        });
        
        // Call deposit
         calls[1] = BatchCallAndSponsor.Call({
            to: address(yTokenGateway),
            value: 0,
            data: abi.encodeCall(yTokenGateway.deposit, (
                address(fakeYieldToken), 
                amount, 
                freshAddressA
            ))
        }); 
        
        bytes memory expectedRevert = abi.encodeWithSignature("Unauthorized(string)", "Not whitelisted");
        executeEIP7702Transaction(freshAddressA, freshPKA, freshPKB, calls, expectedRevert);
    }

    function testYTokenGatewayWithdrawSponsoredTransaction() public {
        uint256 amount = 1000e18;

        uint256 freshPKA = uint256(keccak256(abi.encodePacked("freshA", block.timestamp, "YTokenGatewayWithdraw")));
        address payable freshAddressA = payable(vm.addr(freshPKA));
        
         // Fund with yield tokens
        deal(address(fakeYieldToken), freshAddressA, amount);
        // No need to fund for testing access control
        
        uint256 freshPKB = uint256(keccak256(abi.encodePacked("freshB", block.timestamp, "YTokenGatewayWithdraw")));
        
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);
        
        // Call withdraw
        calls[0] = BatchCallAndSponsor.Call({
            to: address(yTokenGateway),
            value: 0,
            data: abi.encodeCall(yTokenGateway.withdraw, (
                address(fakeYieldToken), 
                amount, 
                freshAddressA
            ))
        }); 
        
        bytes memory expectedRevert = abi.encodeWithSignature("Unauthorized(string)", "Not whitelisted");
        executeEIP7702Transaction(freshAddressA, freshPKA, freshPKB, calls, expectedRevert);
    }

    function testWETHGatewayDepositSponsoredTransaction() public {
        uint256 amount = 1000e18;

        uint256 freshPKA = uint256(keccak256(abi.encodePacked("freshA", block.timestamp, "WETHGatewayDeposit")));
        address payable freshAddressA = payable(vm.addr(freshPKA));
        
        // Fund with WETH
        deal(address(fakeYieldToken), freshAddressA, amount);

        uint256 freshPKB = uint256(keccak256(abi.encodePacked("freshB", block.timestamp, "WETHGatewayDeposit")));

        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);

        // Call depositUnderlying
        calls[0] = BatchCallAndSponsor.Call({
            to: address(wethGateway),
            value: 0,
            data: abi.encodeCall(wethGateway.depositUnderlying, (address(alchemist), address(fakeYieldToken), amount, freshAddressA, 100e18))
        });

        bytes memory expectedRevert = abi.encodeWithSignature("Unauthorized(string)", "Not whitelisted");
        executeEIP7702Transaction(freshAddressA, freshPKA, freshPKB, calls, expectedRevert);
    }

    function testWETHGatewayWithdrawUnderlyingSponsoredTransaction() public {
        uint256 amount = 1000e18;

        uint256 freshPKA = uint256(keccak256(abi.encodePacked("freshA", block.timestamp, "WETHGatewayWithdraw")));
        address payable freshAddressA = payable(vm.addr(freshPKA));
        
        // No need to fund with tokens for testing the access control
        
        uint256 freshPKB = uint256(keccak256(abi.encodePacked("freshB", block.timestamp, "WETHGatewayWithdraw")));

        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);

        // Call withdrawUnderlying
        calls[0] = BatchCallAndSponsor.Call({
            to: address(wethGateway),
            value: 0,
            data: abi.encodeCall(wethGateway.withdrawUnderlying, (
                address(alchemist), 
                address(fakeYieldToken), 
                amount, 
                freshAddressA, 
                100e18
            ))
        });
        bytes memory expectedRevert = abi.encodeWithSignature("Unauthorized(string)", "Not whitelisted");
        executeEIP7702Transaction(freshAddressA, freshPKA, freshPKB, calls, expectedRevert);
    }

    function testAutoleverageCurveMetapool() public {

        // Updating whitelist at the hardcoded address to ensure existence on the tested chain
        vm.etch(0xA3dfCcbad1333DC69997Da28C961FF8B2879e653, address(whitelist).code);
        // Calculate target debt outside the function call to reduce stack variables
        uint256 targetDebt = (TEST_COLLATERAL_TOTAL - TEST_COLLATERAL_INITIAL) * TEST_SLIPPAGE_MULTIPLIER / 10000;
        
        uint256 freshPKA = uint256(keccak256(abi.encodePacked("freshA", block.timestamp, "WETHGatewayWithdraw")));
        address payable freshAddressA = payable(vm.addr(freshPKA));
        
        uint256 freshPKB = uint256(keccak256(abi.encodePacked("freshB", block.timestamp, "WETHGatewayWithdraw")));

        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);

        // Call autoleverage
        calls[0] = BatchCallAndSponsor.Call({
            to: address(metapoolHelper),
            value: 0,
            data: abi.encodeCall(metapoolHelper.autoleverage, (
                metapool,
                metapoolI,
                metapoolJ,
                address(alchemist),
                address(fakeYieldToken), 
                TEST_COLLATERAL_INITIAL,  // Use the constant instead
                TEST_COLLATERAL_TOTAL,    // Use the constant instead
                targetDebt            
            ))
        });
        bytes memory expectedRevert = abi.encodeWithSignature("Unauthorized(address)", freshAddressA);
        // Execute the test using helper function
        executeEIP7702Transaction(freshAddressA, freshPKA, freshPKB, calls, expectedRevert);
    }


    function testAutoleverageCurveFactoryethpool() public {
        // Updating whitelist at the hardcoded address to ensure existence on the tested chain
        vm.etch(0xA3dfCcbad1333DC69997Da28C961FF8B2879e653, address(whitelist).code);
        // Calculate target debt outside the function call to reduce stack variables
        uint256 targetDebt = (TEST_COLLATERAL_TOTAL - TEST_COLLATERAL_INITIAL) * TEST_SLIPPAGE_MULTIPLIER / 10000;
        
        uint256 freshPKA = uint256(keccak256(abi.encodePacked("freshA", block.timestamp, "WETHGatewayWithdraw")));
        address payable freshAddressA = payable(vm.addr(freshPKA));
        
        uint256 freshPKB = uint256(keccak256(abi.encodePacked("freshB", block.timestamp, "WETHGatewayWithdraw")));

        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);

        // Call autoleverage
        calls[0] = BatchCallAndSponsor.Call({
            to: address(factoryethpoolHelper),
            value: 0,
            data: abi.encodeCall(factoryethpoolHelper.autoleverage, (
                factorypool,
                factorypoolI,
                factorypoolJ,
                address(alchemist),
                address(fakeYieldToken), 
                TEST_COLLATERAL_INITIAL,  // Use the constant instead
                TEST_COLLATERAL_TOTAL,    // Use the constant instead
                targetDebt            
            ))
        });
        bytes memory expectedRevert = abi.encodeWithSignature("Unauthorized(address)", freshAddressA);
        // Execute the test using helper function
        executeEIP7702Transaction(freshAddressA, freshPKA, freshPKB, calls, expectedRevert);
    }

    // Helper function to reduce stack depth
    function executeEIP7702Transaction(
        address payable freshAddressA,
        uint256 freshPKA,
        uint256 freshPKB,
        BatchCallAndSponsor.Call[] memory calls,
        bytes memory expectedRevert
    ) private {
        VmSafe.SignedDelegation memory signedDelegation = vm.signDelegation(address(implementation), freshPKA);
        
        vm.startBroadcast(vm.addr(freshPKB));
        vm.attachDelegation(signedDelegation);
        
        // Verify that freshAddressA's account now temporarily behaves as a smart contract.
        bytes memory code = address(freshAddressA).code;
        require(code.length > 0, "no code written to freshAddressA");
        
        bytes memory encodedCalls = "";
        for (uint256 i = 0; i < calls.length; i++) {    
            encodedCalls = abi.encodePacked(encodedCalls, calls[i].to, calls[i].value, calls[i].data);
        }
        
        bytes32 digest = keccak256(abi.encodePacked(BatchCallAndSponsor(freshAddressA).nonce(), encodedCalls));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freshPKA, ECDSA.toEthSignedMessageHash(digest));
        bytes memory signature = abi.encodePacked(r, s, v);         

        // Expect the same Unauthorized error 
        vm.expectRevert(expectedRevert);
        BatchCallAndSponsor(freshAddressA).execute(calls, signature);
        vm.stopBroadcast();
    }
}