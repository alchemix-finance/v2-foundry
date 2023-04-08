// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {HarvestResolver} from "../keepers/HarvestResolver.sol";

import {YearnTokenAdapterOptimism} from "../adapters/yearn/YearnTokenAdapterOptimism.sol";

import {
    OptimismYearnRewardCollector,
    InitializationParams as RewardCollectorInitializationParams
} from "../utils/collectors/OptimismYearnRewardCollector.sol";

import {RewardRouter} from "../utils/RewardRouter.sol";

import {AlchemicTokenV2} from "../AlchemicTokenV2.sol";
import {AlchemistV2} from "../AlchemistV2.sol";
import {TransmuterV2} from "../TransmuterV2.sol";
import {TransmuterBuffer} from "../TransmuterBuffer.sol";
import {Whitelist} from "../utils/Whitelist.sol";
import {YearnStakingToken} from "../external/yearn/YearnStakingToken.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemicToken} from "../interfaces/IAlchemicToken.sol";
import {IAlchemixHarvester} from "../interfaces/keepers/IAlchemixHarvester.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import "../interfaces/IERC20TokenReceiver.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract YearnOptimismTest is DSTestPlus {    
    uint256 constant BPS = 10000;
    address constant alchemistAlUSD = 0x10294d57A419C8eb78C648372c5bAA27fD1484af;
    address constant alchemistAlETH = 0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4;
    address constant alchemistAdmin = 0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a;
    address constant alchemistAlUSDWhitelist = 0xc3365984110dB9b84c7e3Fc1cffb370C6Df6380F;
    address constant alchemistAlETHWhitelist = 0xc5fE32e46fD226364BFf7A035e8Ca2aBE390a68f;
    address constant alchemixHarvester = 0x99e7D40750682fF6b5b8c362dAAd265b9B21e1a0;
    address constant alUSD = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address constant dai = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address constant usdt = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
    address constant stakingRewardsDai = 0xf8126EF025651E1B313a6893Fcf4034F4F4bD2aA;
    address constant weth = 0x4200000000000000000000000000000000000006;
    address constant yvDAI = 0x65343F414FFD6c97b0f6add33d16F6845Ac22BAc;
    address constant rewardToken = 0x4200000000000000000000000000000000000042;
    address constant velodromeRouter = 0x9c12939390052919aF3155f41Bf4160Fd3666A6f;

    IAlchemistV2 alchemistUSD;
    IAlchemistV2 alchemistETH;
    OptimismYearnRewardCollector rewardCollector;
    RewardRouter rewardRouter;
    YearnTokenAdapterOptimism adapter;
    HarvestResolver harvestResolver;
    YearnStakingToken stakingToken;
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

        stakingToken = new YearnStakingToken(
            stakingRewardsDai,
            yvDAI,
            dai,
            rewardToken,
            address(this),
            "yearnStakingDai",
            "ySDai"
        );

        rewardCollector = new OptimismYearnRewardCollector(rewardCollectorParams);

        rewardRouter = new RewardRouter();

        rewardRouter.addVault(address(stakingToken), address(rewardCollector), 0, 0, 0);

        hevm.startPrank(alchemistAdmin);
        whitelist.add(address(this));
        whitelist.add(address(rewardCollector));
        hevm.stopPrank();

        hevm.prank(0xb31aCbB06fCF38Bc6a93F198Ec3805AdBF2DAA7C);
        IAlchemixHarvester(alchemixHarvester).setRewardRouter(address(rewardRouter));

        hevm.startPrank(alchemistAdmin);
        IAlchemicToken(alUSD).setWhitelist(address(this), true);
        IAlchemicToken(alUSD).setWhitelist(address(rewardCollector), true);
        IAlchemicToken(alUSD).setWhitelist(address(alchemistUSD), true);
        hevm.stopPrank();

        hevm.startPrank(address(rewardCollector));
        TokenUtils.safeApprove(rewardToken, velodromeRouter, 2**256 - 1);
        TokenUtils.safeApprove(alUSD, address(alchemistUSD), 2**256 - 1);
        hevm.stopPrank();

        adapter = new YearnTokenAdapterOptimism(address(stakingToken), dai);
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
            amount < 10000000e18
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
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(this));
        // assertGt(unwrapped, 1000e18);
    }

    // TODO: Add integration tests and reward collector tests after upgrading the collector and harvester
}