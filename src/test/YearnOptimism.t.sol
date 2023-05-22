// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {AlchemixHarvester} from "../keepers/AlchemixHarvester.sol";
import {HarvestResolver} from "../keepers/HarvestResolver.sol";

import {
    YearnTokenAdapterOptimism
} from "../adapters/yearn/YearnTokenAdapterOptimism.sol";

import {
    RewardCollectorOptimism,
    InitializationParams as RewardCollectorInitializationParams
} from "../utils/RewardCollectorOptimism.sol";

import {AlchemicTokenV2} from "../AlchemicTokenV2.sol";
import {AlchemistV2} from "../AlchemistV2.sol";
import {TransmuterV2} from "../TransmuterV2.sol";
import {TransmuterBuffer} from "../TransmuterBuffer.sol";
import {Whitelist} from "../utils/Whitelist.sol";
import {YearnStakingToken} from "../external/yearn/YearnStakingToken.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemicToken} from "../interfaces/IAlchemicToken.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import "../interfaces/IERC20TokenReceiver.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract YearnOptimismTest is DSTestPlus {
    // These are for mainnet change once deployed on optimism
    address constant alchemistAlUSD = 0x10294d57A419C8eb78C648372c5bAA27fD1484af;
    address constant alchemistAlETH = 0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4;
    address constant alchemistAdmin = 0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a;
    address constant alchemistAlUSDWhitelist = 0xc3365984110dB9b84c7e3Fc1cffb370C6Df6380F;
    address constant alchemistAlETHWhitelist = 0xc5fE32e46fD226364BFf7A035e8Ca2aBE390a68f;
    uint256 constant BPS = 10000;
    address constant alUSD = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address constant dai = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // Optimism DAI
    address constant usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address constant usdt = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
    address constant weth = 0x4200000000000000000000000000000000000006;
    address constant yvDAI = 0x65343F414FFD6c97b0f6add33d16F6845Ac22BAc;
    // address constant yUSDC = ;
    address constant rewardsController = 0x929EC64c34a17401F460460D4B9390518E5B473e;
    address constant rewardToken = 0x4200000000000000000000000000000000000042;
    address constant rewardVault = 0x7D2382b1f8Af621229d33464340541Db362B4907;
    address constant velodromeRouter = 0x9c12939390052919aF3155f41Bf4160Fd3666A6f;

    IAlchemistV2 alchemistUSD;
    IAlchemistV2 alchemistETH;
    AlchemixHarvester harvester;
    YearnTokenAdapterOptimism adapter;
    HarvestResolver harvestResolver;
    YearnStakingToken stakingToken;
    RewardCollectorOptimism rewardCollector;
    TransmuterV2 transmuter;
    TransmuterBuffer buffer;
    IWhitelist whitelist;

    function setUp() external {
        whitelist = IWhitelist(alchemistAlUSDWhitelist);
        
		alchemistUSD = IAlchemistV2(alchemistAlUSD);
		alchemistETH = AlchemistV2(alchemistAlETH);

        RewardCollectorInitializationParams memory rewardCollectorParams = RewardCollectorInitializationParams({
            alchemist:          address(alchemistUSD),
            debtToken:          alUSD,
            rewardToken:        rewardToken,
            swapRouter:         velodromeRouter
        });

<<<<<<< HEAD
        rewardCollector = new RewardCollectorOptimism(rewardCollectorParams);
=======
        stakingToken = new YearnStakingToken(
            stakingRewardsDai,
            yvDAI,
            dai,
            rewardToken,
            rewardVault,
            address(this),
            "yearnStakingDai",
            "ySDai"
        );
>>>>>>> 96fd20e (YToken Gateway added and tested)

        hevm.startPrank(0x7a6468F8161ef39d7639c67DfA5637BA1b7ba74B);
        whitelist.add(address(this));
        whitelist.add(address(rewardCollector));
        hevm.stopPrank();

<<<<<<< HEAD
=======

>>>>>>> 96fd20e (YToken Gateway added and tested)
        hevm.startPrank(alchemistAdmin);
        IAlchemicToken(alUSD).setWhitelist(address(this), true);
        IAlchemicToken(alUSD).setWhitelist(address(rewardCollector), true);
        IAlchemicToken(alUSD).setWhitelist(address(alchemistUSD), true);
        hevm.stopPrank();

        hevm.startPrank(address(rewardCollector));
        TokenUtils.safeApprove(rewardToken, velodromeRouter, 2**256 - 1);
        TokenUtils.safeApprove(alUSD, address(alchemistUSD), 2**256 - 1);
        hevm.stopPrank();

        stakingToken = new YearnStakingToken(
            0x1eC8BaAB7DBd6f5a02EfcAb711e765bF796d091c,
            yvDAI,
            dai,
            rewardToken,
            address(this),
            "yearnStakingDai",
            "ySDai"
        );

        adapter = new YearnTokenAdapterOptimism(address(stakingToken), dai);

        IAlchemistV2AdminActions.YieldTokenConfig memory yieldConfig = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000000 ether,
            creditUnlockBlocks: 7200
		});


        hevm.startPrank(alchemistAdmin);
        alchemistUSD.addYieldToken(address(stakingToken), yieldConfig);
        alchemistUSD.setYieldTokenEnabled(address(stakingToken), true);
        hevm.stopPrank();
    }

    function testRoundTrip() external {
        uint256 depositAmount = 1e18;

        deal(dai, address(this), depositAmount);

        SafeERC20.safeApprove(dai, address(adapter), depositAmount);
        uint256 wrapped = adapter.wrap(depositAmount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(stakingToken));
        assertGe(depositAmount, underlyingValue);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped);
        assertEq(stakingToken.balanceOf(address(this)), 0);
        assertEq(stakingToken.balanceOf(address(adapter)), 0);
    }

    function testRoundTripFuzz(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(dai) && 
            amount < 1000000e18
        );
        
        deal(dai, address(this), amount);

        SafeERC20.safeApprove(dai, address(adapter), amount);
        uint256 wrapped = adapter.wrap(amount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(stakingToken));
        assertApproxEq(amount, underlyingValue, amount * 10000 / 1e18);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertApproxEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped, 10000);
        assertEq(stakingToken.balanceOf(address(this)), 0);
        assertEq(stakingToken.balanceOf(address(adapter)), 0);
    }

    function testAppreciation() external {
        deal(dai, address(this), 1000e18);

        SafeERC20.safeApprove(dai, address(adapter), 1000e18);
        uint256 wrapped = adapter.wrap(1000e18, address(this));
        assertEq(IERC20(dai).balanceOf(address(this)), 0);
        
        hevm.roll(block.number + 100000);
        hevm.warp(block.timestamp + 10000 days);

        assertGt(stakingToken.claimRewards(), 0);
        assertGt(IERC20(0x4200000000000000000000000000000000000042).balanceOf(address(this)), 0);
    }

    function testRoundTripIntegrated() external {
        uint256 amount = 1000e18;

        deal(dai, address(this), amount);

        SafeERC20.safeApprove(dai, address(alchemistUSD), amount);
        uint256 shares = alchemistUSD.depositUnderlying(address(stakingToken), amount, address(this), 0);

        hevm.roll(block.number + 100000);
        hevm.warp(block.timestamp + 10000 days);

        uint256 underlyingWithdrawn = alchemistUSD.withdrawUnderlying(address(stakingToken), shares, address(this), 0);
        assertApproxEq(underlyingWithdrawn, amount, 10);
    }
}