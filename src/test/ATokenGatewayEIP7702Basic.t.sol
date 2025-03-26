// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13 <0.9.0;
import {Test, console2} from "./../../lib/forge-std/src/Test.sol"; 
import {VmSafe} from "./../../lib/forge-std/src/Vm.sol";
import {BatchCallAndSponsor} from "./mocks/BatchCallAndSponsor.sol";
import {ERC20} from "./../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { CheatCodes } from "../test/utils/Cheatcodes.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol"; 
import { AlchemistV2 } from "../AlchemistV2.sol";
import { AlchemicTokenV2 } from "../AlchemicTokenV2.sol";
import { TransmuterV2 } from "../TransmuterV2.sol";
import { TransmuterBuffer } from "../TransmuterBuffer.sol";
import { Whitelist } from "../utils/Whitelist.sol";
import { TestERC20 } from "../test/mocks/TestERC20.sol";
import { TestYieldToken } from "../test/mocks/TestYieldToken.sol";
import { TestYieldTokenAdapter } from "../test/mocks/TestYieldTokenAdapter.sol";
import { IERC20Mintable } from "../interfaces/IERC20Mintable.sol";
import { ITokenAdapter } from "../interfaces/ITokenAdapter.sol";
import { IAlchemistV2AdminActions } from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import { IAlchemistV2 } from "../interfaces/IAlchemistV2.sol";
import "../../lib/forge-std/src/Test.sol";
import {ITestYieldToken} from "../interfaces/test/ITestYieldToken.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {Unauthorized} from "../base/errors.sol";
import {ECDSA} from "./../../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "./../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    AAVETokenAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/aave/AAVETokenAdapter.sol";

import {StaticAToken} from "../external/aave/StaticAToken.sol";
import {ILendingPool} from "../interfaces/external/aave/ILendingPool.sol";
import {ITokenGateway} from "../interfaces/ITokenGateway.sol";
import {ATokenGateway} from "../adapters/aave/ATokenGateway.sol";




contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// FOUNDRY_PROFILE=lite forge test --fork-url https://eth-sepolia.g.alchemy.com/v2/aOdjhvcm7-q8A0YTkfmWI5JfQIcGaP1h --match-path src/test/BatchCallAndSponsorTest.t.sol  -vvvv --evm-version prague --fork-block-number 7882137


contract ATokenGatewayEIP7702Basic is Test {
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

    
    // AToken Gateway
    uint256 constant BPS = 10000;
    address constant dai = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357; //  Sepolia AAVE V3 DAI
    address constant aToken = 0x29598b72eb5CeBd806C5dCD549490FdA35B13cD8;  // Sepolia AAVE V3 aDAI 
    ILendingPool lendingPool = ILendingPool(0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951); // Sepolia Aave V3 Lending Pool
    string wrappedTokenName = "staticAaveDai";
    string wrappedTokenSymbol = "saDAI";
    StaticAToken staticAToken;
    AAVETokenAdapter tokenAdapter;
    ITokenGateway gateway;

    event CallExecuted(address indexed to, uint256 value, bytes data);
    event BatchExecuted(uint256 indexed nonce, BatchCallAndSponsor.Call[] calls);


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

        // Test tokens
        fakeUnderlyingToken = address(dai);
        fakeYieldToken = address(aToken);

        // Contracts and logic contracts
        alOwner = caller;
        alToken = new AlchemicTokenV2(_name, _symbol, _flashFee);
        transmuterBufferLogic = new TransmuterBuffer();
        transmuterLogic = new TransmuterV2();
        alchemistLogic = new AlchemistV2();
        whitelist = new Whitelist();


        staticAToken = new StaticAToken(
            lendingPool,
            aToken,
            wrappedTokenName,
            wrappedTokenSymbol
        );
        tokenAdapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:       address(alchemist),
            token:           address(staticAToken),
            underlyingToken: address(dai)
        }));

        IAlchemistV2.YieldTokenConfig memory yieldTokenConfig = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(tokenAdapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });
        

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
        gateway = new ATokenGateway(address(whitelist), address(alchemist));


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
        alchemist.addYieldToken(address(staticAToken), yieldTokenConfig);
        alchemist.setYieldTokenEnabled(address(staticAToken), true);
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
        whitelist.add(address(gateway));
        vm.stopPrank();
    }

    function setUp() public {
        // Deploy the Alchemix V2 contract
        deployAlchemixV2Contracts();

         // Deploy the delegation contract (AddressA will delegate calls to this contract).
        implementation = new BatchCallAndSponsor();
    }

 
    function testDepositWithFreshAddressPureEOA() public {
        // Generate a new private key and address
        uint256 freshPK = uint256(keccak256(abi.encodePacked("fresh", block.timestamp)));
        address freshAddress = vm.addr(freshPK);
        
        require(address(freshAddress).code.length == 0, "There is no code written to freshAddress");
        uint256 amount = 1000e18;

        // Fund the fresh address
        deal(dai, freshAddress, amount);        
        // Test with the fresh address. Tx.origin will be freshAddress
        vm.startBroadcast(freshPK);
        SafeERC20.safeApprove(address(dai), address(lendingPool), amount);
       // Now, both msg.sender and tx.origin will be freshAddress.
        lendingPool.deposit(dai, amount, freshAddress, 0);
        uint256 startBal = IERC20(aToken).balanceOf(freshAddress);
        SafeERC20.safeApprove(address(aToken), address(gateway), startBal);
        uint256 price = alchemist.getUnderlyingTokensPerShare(address(staticAToken));
        uint256 sharesIssued = gateway.deposit(address(staticAToken), startBal, freshAddress);
        uint256 expectedValue = sharesIssued * price / 1e18;
        vm.stopBroadcast();

        // Validate that the deposit occurred.
        assertApproxEqAbs(amount, expectedValue, 1e18);

    }  


    function testDepositWithFreshAddressSponsoredTransaction() public {
        // Generate a new private key and address
        uint256 freshPKA = uint256(keccak256(abi.encodePacked("freshA", block.timestamp)));
        address payable freshAddressA = payable(vm.addr(freshPKA));
        
        console2.log("Fresh address A code length:", address(freshAddressA).code.length);
        
        uint256 amount = 1000e18;
        // Fund the fresh address
        deal(dai, freshAddressA, amount);        


         // Generate a new private key and address
        uint256 freshPKB = uint256(keccak256(abi.encodePacked("freshB", block.timestamp)));
        address freshAddressB = vm.addr(freshPKB);
        
        console2.log("Fresh address B code length:", address(freshAddressB).code.length);
        
        
        // Setup the call to the ATokenGateway deposit function
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](4); 
        
        // First approve the alchemist to spend freshAddressA tokens 
        calls[0] = BatchCallAndSponsor.Call({
            to: dai, 
            value: 0,
            data: abi.encodeCall(ERC20.approve, (address(lendingPool), amount))
        });
        
        // Then call deposit function on the lending pool
        calls[1] = BatchCallAndSponsor.Call({
            to: address(lendingPool),
            value: 0,
            data: abi.encodeCall(lendingPool.deposit, (dai, amount, freshAddressA, 0))
        });

        calls[2] = BatchCallAndSponsor.Call({
            to: address(aToken), 
            value: 0,
            data: abi.encodeCall(ERC20.approve, (address(gateway), 100e18))
        });
        
        // Then call deposit function on the ATokenGateway 
        calls[3] = BatchCallAndSponsor.Call({
            to: address(gateway),
            value: 0,
            data: abi.encodeCall(ATokenGateway.deposit, (address(staticAToken), 100e18, freshAddressA))
        });
        
        
        // FreshAddressA signs a delegation allowing `implementation` to execute transactions on freshAddressA's behalf.
        VmSafe.SignedDelegation memory signedDelegation = vm.signDelegation(address(implementation), freshPKA); 
        
        // FreshAddressB attaches the signed delegation from freshAddressA and broadcasts it.
        vm.startBroadcast(freshPKB);
        vm.attachDelegation(signedDelegation);
        
        // Verify that freshAddressA's account now temporarily behaves as a smart contract.
        bytes memory code = address(freshAddressA).code;
        require(code.length > 0, "no code written to freshAddressA");
        
        // Build the encoded call data for signature
        bytes memory encodedCalls = "";
        for (uint256 i = 0; i < calls.length; i++) {
            encodedCalls = abi.encodePacked(encodedCalls, calls[i].to, calls[i].value, calls[i].data);
        }
        
        bytes32 digest = keccak256(abi.encodePacked(BatchCallAndSponsor(freshAddressA).nonce(), encodedCalls));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freshPKA, ECDSA.toEthSignedMessageHash(digest));
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert("Call reverted"); 
        
        // As freshAddressB, execute the transaction via freshAddressA's temporarily assigned contract.
        BatchCallAndSponsor(freshAddressA).execute(calls, signature);   
        
        vm.stopBroadcast();
    } 



}