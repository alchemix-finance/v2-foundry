// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {AlchemixHarvesterOptimism} from "../keepers/AlchemixHarvesterOptimism.sol";
import {HarvestResolverOptimism} from "../keepers/HarvestResolverOptimism.sol";

import {
    AAVETokenAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/aave/AAVETokenAdapter.sol";

import {
    RewardCollectorOptimism,
    InitializationParams as RewardCollectorInitializationParams
} from "../utils/RewardCollectorOptimism.sol";

import {AlchemicTokenV2} from "../AlchemicTokenV2.sol";
import {AlchemistV2} from "../AlchemistV2.sol";
import {StaticATokenV3} from "../external/aave/StaticATokenV3.sol";
import {TransmuterV2} from "../TransmuterV2.sol";
import {TransmuterBuffer} from "../TransmuterBuffer.sol";
import {Whitelist} from "../utils/Whitelist.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemicToken} from "../interfaces/IAlchemicToken.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import "../interfaces/IERC20TokenReceiver.sol";
import {ILendingPool} from "../interfaces/external/aave/ILendingPool.sol";
import {IRewardsController} from "../interfaces/external/aave/IRewardsController.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract AaveV3TokenAdapterTest is DSTestPlus, IERC20TokenReceiver {
    // These are for mainnet change once deployed on optimism
    // address constant alchemistAlUSD = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    // address constant alchemistAlETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant alchemistAdmin = 0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a;
    // address constant alchemistAlUSDWhitelist = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    // address constant alchemistAlETHWhitelist = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;
    uint256 constant BPS = 10000;
    address constant alUSD = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address constant dai = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // Optimism DAI
    address constant aOptDAI = 0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE;
    address constant usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address constant aOptUSDC = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address constant usdt = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
    address constant aOptUSDT = 0x6ab707Aca953eDAeFBc4fD23bA73294241490620;
    address constant weth = 0x4200000000000000000000000000000000000006;
    address constant aOptWETH = 0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8;
    address constant rewardsController = 0x929EC64c34a17401F460460D4B9390518E5B473e;
    address constant rewardToken = 0x4200000000000000000000000000000000000042;
    address constant velodromeRouter = 0x9c12939390052919aF3155f41Bf4160Fd3666A6f;

    AlchemistV2 alchemistUSD;
    AlchemistV2 alchemistETH;
    AlchemixHarvesterOptimism harvester;
    AAVETokenAdapter adapter;
    HarvestResolverOptimism harvestResolver;
    StaticATokenV3 staticAToken;
    RewardCollectorOptimism rewardCollector;
    TransmuterV2 transmuter;
    TransmuterBuffer buffer;
    ILendingPool lendingPool = ILendingPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    Whitelist whitelist;

    function setUp() external {
        whitelist = new Whitelist();

        // Set up buffer and transmuter
        TransmuterBuffer transmuterBuffer = new TransmuterBuffer();
        bytes memory bufferParams = abi.encodeWithSelector(TransmuterBuffer.initialize.selector, address(this), alUSD);
		TransparentUpgradeableProxy proxyBuffer = new TransparentUpgradeableProxy(address(transmuterBuffer), alchemistAdmin, bufferParams);
		buffer = TransmuterBuffer(address(proxyBuffer));
        transmuter = new TransmuterV2();
        
		IAlchemistV2AdminActions.InitializationParams memory params = IAlchemistV2AdminActions.InitializationParams({
			admin: address(this),
			debtToken: alUSD,
			transmuter: address(this),
			minimumCollateralization: 2 * 1e18,
			protocolFee: 1000,
			protocolFeeReceiver: address(this),
			mintingLimitMinimum: 1,
			mintingLimitMaximum: uint256(type(uint160).max),
			mintingLimitBlocks: 300,
			whitelist: address(whitelist)
		});

        // Set up proxy to add params
        AlchemistV2 alch = new AlchemistV2();
        bytes memory alchemParams = abi.encodeWithSelector(AlchemistV2.initialize.selector, params);
		TransparentUpgradeableProxy proxyAlchemistUSD = new TransparentUpgradeableProxy(address(alch), alchemistAdmin, alchemParams);
		alchemistUSD = AlchemistV2(address(proxyAlchemistUSD));
        TransparentUpgradeableProxy proxyAlchemistETH = new TransparentUpgradeableProxy(address(alch), alchemistAdmin, alchemParams);
		alchemistETH = AlchemistV2(address(proxyAlchemistETH));

        RewardCollectorInitializationParams memory rewardCollectorParams = RewardCollectorInitializationParams({
            alchemist:          address(alchemistUSD),
            debtToken:          alUSD,
            rewardToken:        rewardToken,
            swapRouter:         velodromeRouter
        });

        rewardCollector = new RewardCollectorOptimism(rewardCollectorParams);

        whitelist.add(address(this));
        whitelist.add(address(rewardCollector));
        hevm.startPrank(alchemistAdmin);
        IAlchemicToken(alUSD).setWhitelist(address(this), true);
        IAlchemicToken(alUSD).setWhitelist(address(rewardCollector), true);
        IAlchemicToken(alUSD).setWhitelist(address(alchemistUSD), true);
        hevm.stopPrank();

        hevm.startPrank(address(rewardCollector));
        TokenUtils.safeApprove(rewardToken, velodromeRouter, 2**256 - 1);
        TokenUtils.safeApprove(alUSD, address(alchemistUSD), 2**256 - 1);
        hevm.stopPrank();

        staticAToken = new StaticATokenV3(
            address(lendingPool),
            rewardsController,
            aOptDAI,
            address(rewardCollector),
            "staticAaveOptimismDai",
            "aOptDai"
        );

        adapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:          address(this),
            token:              address(staticAToken),
            underlyingToken:    dai
        }));

        IAlchemistV2AdminActions.UnderlyingTokenConfig memory underlyingConfig = IAlchemistV2AdminActions.UnderlyingTokenConfig({
			repayLimitMinimum: 1,
			repayLimitMaximum: 1000,
			repayLimitBlocks: 10,
			liquidationLimitMinimum: 1,
			liquidationLimitMaximum: 1000,
			liquidationLimitBlocks: 7200
		});

		alchemistUSD.addUnderlyingToken(dai, underlyingConfig);
        alchemistUSD.setUnderlyingTokenEnabled(dai, true);
        alchemistUSD.addUnderlyingToken(usdc, underlyingConfig);
        alchemistUSD.setUnderlyingTokenEnabled(usdc, true);
		alchemistUSD.addUnderlyingToken(usdt, underlyingConfig);
        alchemistUSD.setUnderlyingTokenEnabled(usdt, true);
        alchemistETH.addUnderlyingToken(weth, underlyingConfig);
        alchemistETH.setUnderlyingTokenEnabled(weth, true);

        hevm.label(0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE, "aOptDAI");
        hevm.label(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1, "DAI");
        hevm.label(0x625E7708f30cA75bfd92586e17077590C60eb4cD, "aOptUSDC");
        hevm.label(0x7F5c764cBc14f9669B88837ca1490cCa17c31607, "USDC");
        hevm.label(0x6ab707Aca953eDAeFBc4fD23bA73294241490620, "aOptUSDT");
        hevm.label(0x94b008aA00579c1307B0EF2c499aD98a8ce58e58, "USDT");
        hevm.label(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8, "aOptWETH");
        hevm.label(0x4200000000000000000000000000000000000006, "WETH");
    }

    function testTokenDai() external {
        runTokenTest(alchemistUSD, aOptDAI, dai, "Static Aave Optimism DAI", "saOptDAI", 1000 ether);
    }

    function testTokenUsdc() external {
        runTokenTest(alchemistUSD, aOptUSDC, usdc, "Static Aave Optimism USDC", "saUSDC", 1000000000);
    }

    function testTokenUsdt() external {
        runTokenTest(alchemistUSD, aOptUSDT, usdt, "Static Aave Optimism USDT", "saUSDT", 1000000000);
    }

    function testTokenWeth() external {
        runTokenTest(alchemistETH, aOptWETH, weth, "Static Aave Optimis WETH", "saWETH", 1000 ether);
    }

    function runTokenTest(AlchemistV2 alchemist, address aToken, address underlyingToken, string memory name, string memory symbol, uint256 amount) internal {
        StaticATokenV3 newStaticAToken = new StaticATokenV3(
            address(lendingPool),
            rewardsController,
            aToken,
            address(rewardCollector),
            name,
            symbol
        );
        AAVETokenAdapter newAdapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:          address(alchemist),
            token:              address(newStaticAToken),
            underlyingToken:    underlyingToken
        }));
        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(newAdapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });

        alchemist.addYieldToken(address(newStaticAToken), ytc);
        alchemist.setYieldTokenEnabled(address(newStaticAToken), true);

        deal(underlyingToken, address(this), amount);
        uint256 startPrice = alchemist.getUnderlyingTokensPerShare(address(newStaticAToken));
        TokenUtils.safeApprove(underlyingToken, address(alchemist), amount);
        alchemist.depositUnderlying(address(newStaticAToken), amount, address(this), 0);
        (uint256 startShares, ) = alchemist.positions(address(this), address(newStaticAToken));
        uint256 expectedValue = startShares * startPrice / (10 ** newStaticAToken.decimals());
        assertApproxEq(amount, expectedValue, 1000);

        uint256 startBal = IERC20(underlyingToken).balanceOf(address(this));
        assertEq(startBal, 0);

        alchemist.withdrawUnderlying(address(newStaticAToken), startShares, address(this), 0);
        (uint256 endShares, ) = alchemist.positions(address(this), address(newStaticAToken));
        assertEq(endShares, 0);

        uint256 endBal = IERC20(underlyingToken).balanceOf(address(this));
        assertApproxEq(endBal, amount, 1);
    }

    function testRoundTrip() external {
        uint256 depositAmount = 1e18;

        deal(dai, address(this), depositAmount);

        SafeERC20.safeApprove(dai, address(adapter), depositAmount);
        uint256 wrapped = adapter.wrap(depositAmount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(staticAToken));
        assertGe(depositAmount, underlyingValue);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped);
        assertEq(staticAToken.balanceOf(address(this)), 0);
        assertEq(staticAToken.balanceOf(address(adapter)), 0);
    }

    function testRoundTripFuzz(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(dai) && 
            amount < 1000000000e18
        );
        
        deal(dai, address(this), amount);

        SafeERC20.safeApprove(dai, address(adapter), amount);
        uint256 wrapped = adapter.wrap(amount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(staticAToken));
        assertApproxEq(amount, underlyingValue, amount * 10000 / 1e18);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertApproxEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped, 10000);
        assertEq(staticAToken.balanceOf(address(this)), 0);
        assertEq(staticAToken.balanceOf(address(adapter)), 0);
    }

    function testAppreciation() external {
        deal(dai, address(this), 1000e18);

        SafeERC20.safeApprove(dai, address(adapter), 1000e18);
        uint256 wrapped = adapter.wrap(1000e18, address(this));
        
        hevm.roll(block.number + 10000000000);
        hevm.warp(block.timestamp + 1000000000);

        address[] memory assets = new address[](1);
        assets[0] = aOptDAI;

        assertGt(IRewardsController(rewardsController).getUserRewards(assets, address(staticAToken), rewardToken), 0);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        assertGt(unwrapped, 1000e18);
    }

    function testRewardCollector() external {
        AAVETokenAdapter rewardCollectorAdapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:          address(alchemistUSD),
            token:              address(staticAToken),
            underlyingToken:    dai
        }));

        IAlchemistV2AdminActions.YieldTokenConfig memory yieldConfig = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(rewardCollectorAdapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000000 ether,
            creditUnlockBlocks: 7200
		});

        alchemistUSD.addYieldToken(address(staticAToken), yieldConfig);
        alchemistUSD.setYieldTokenEnabled(address(staticAToken), true);

        deal(dai, address(this), 1000000e18);
        SafeERC20.safeApprove(dai, address(alchemistUSD), 1000000e18);
        alchemistUSD.depositUnderlying(address(staticAToken), 1000000e18, address(this), 0);

        alchemistUSD.mint(400000e18, address(this));

        hevm.roll(block.number + 10000000);
        hevm.warp(block.timestamp + 10000000);

        // Keeper check balance of token
        uint256 rewards = IRewardsController(rewardsController).getUserAccruedRewards(address(staticAToken), rewardToken);
        (int256 debtBefore, ) = alchemistUSD.accounts(address((this)));

        rewardCollector.claimAndDistributeRewards(address(staticAToken), rewards * 9999 / 10000);
        (int256 debtAfter, ) = alchemistUSD.accounts(address((this)));

        assertEq(IERC20(rewardToken).balanceOf(address(rewardCollector)), 0);
        assertEq(IERC20(alUSD).balanceOf(address(rewardCollector)), 0);
        assertEq(IERC20(usdc).balanceOf(address(rewardCollector)), 0);
        assertGt(debtBefore, debtAfter);
    }

    function testRewardCollectorWithHarvester() external {
        AAVETokenAdapter rewardCollectorAdapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:          address(alchemistUSD),
            token:              address(staticAToken),
            underlyingToken:    dai
        }));

        IAlchemistV2AdminActions.YieldTokenConfig memory yieldConfig = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(rewardCollectorAdapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000000 ether,
            creditUnlockBlocks: 7200
		});

        alchemistUSD.addYieldToken(address(staticAToken), yieldConfig);
        alchemistUSD.setYieldTokenEnabled(address(staticAToken), true);

        buffer.setSource(address(alchemistUSD), true);

        // Keepers
        harvestResolver = new HarvestResolverOptimism();
        harvester = new AlchemixHarvesterOptimism(address(this), 100000e18, address(harvestResolver));
        harvestResolver.setHarvester(address(harvester), true);
        harvestResolver.addHarvestJob(true, address(alchemistUSD), address(rewardCollector), address(staticAToken), aOptDAI, 1000, 0, 0);
        alchemistUSD.setKeeper(address(harvester), true);

        harvester.addRewardCollector(address(staticAToken), rewardToken);

        deal(dai, address(this), 1000000e18);
        SafeERC20.safeApprove(dai, address(alchemistUSD), 1000000e18);
        alchemistUSD.depositUnderlying(address(staticAToken), 1000000e18, address(this), 0);

        alchemistUSD.mint(400000e18, address(this));

        hevm.roll(block.number + 10000000);
        hevm.warp(block.timestamp + 10000000);

        // Keeper check balance of token
        (bool canExec, bytes memory execPayload) = harvestResolver.checker();

        (address alch, address yield, uint256 minOut, uint256 expectedExchange) = abi.decode(extractCalldata(execPayload), (address, address, uint256, uint256));

        (int256 debtBefore, ) = alchemistUSD.accounts(address((this)));
        harvester.harvest(alch, yield, minOut, expectedExchange);
        (int256 debtAfter, ) = alchemistUSD.accounts(address((this)));

        assertEq(IERC20(rewardToken).balanceOf(address(rewardCollector)), 0);
        assertEq(IERC20(alUSD).balanceOf(address(rewardCollector)), 0);
        assertEq(IERC20(usdc).balanceOf(address(rewardCollector)), 0);
        assertGt(debtBefore, debtAfter);
    }

    // For decoding bytes that have selector header
    function extractCalldata(bytes memory calldataWithSelector) internal pure returns (bytes memory) {
        bytes memory calldataWithoutSelector;

        require(calldataWithSelector.length >= 4);

        assembly {
            let totalLength := mload(calldataWithSelector)
            let targetLength := sub(totalLength, 4)
            calldataWithoutSelector := mload(0x40)
            
            mstore(calldataWithoutSelector, targetLength)

            mstore(0x40, add(0x20, targetLength))

            mstore(add(calldataWithoutSelector, 0x20), shl(0x20, mload(add(calldataWithSelector, 0x20))))

            for { let i := 0x1C } lt(i, targetLength) { i := add(i, 0x20) } {
                mstore(add(add(calldataWithoutSelector, 0x20), i), mload(add(add(calldataWithSelector, 0x20), add(i, 0x04))))
            }
        }

        return calldataWithoutSelector;
    }

    function onERC20Received(address token, uint256 value) external {
        return;
    }
}