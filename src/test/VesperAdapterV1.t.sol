// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {AlchemistV2} from "../AlchemistV2.sol";
import {AlchemixHarvester} from "../keepers/AlchemixHarvester.sol";
import {HarvestResolver} from "../keepers/HarvestResolver.sol";

import {
    RewardCollectorVesper,
    InitializationParams as RewardcollectorParams
} from "../utils/RewardCollectorVesper.sol";

import {UniswapEstimatedPrice} from "../utils/UniswapEstimatedPrice.sol";

import {
    VesperAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/vesper/VesperAdapterV1.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IProxyAdmin} from "../interfaces/external/IProxyAdmin.sol";
import {ISwapRouter} from "../interfaces/external/uniswap/ISwapRouter.sol";
import {IUniswapV3Factory} from "../interfaces/external/uniswap/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../interfaces/external/uniswap/IUniswapV3Pool.sol";
import {IVesperPool} from "../interfaces/external/vesper/IVesperPool.sol";
import {IVesperRewards} from "../interfaces/external/vesper/IVesperRewards.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract VesperAdapterV1Test is DSTestPlus {
    uint256 constant BPS = 10000;
    address constant ADMIN = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant alEthAddress = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant alUsdAddress = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address constant alchemistETHAddress = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant alchemistUSDAddress =0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant proxyAdminAddress = 0xE0fC5CB7665041CdA26969A2D1ceb5cD5046347d;
    address constant uniSwapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant uniswapRouter = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant vaDAI = 0x0538C8bAc84E95A9dF8aC10Aad17DbE81b9E36ee;
    address constant vaUSDC = 0xa8b607Aa09B6A2E306F93e74c282Fb13f6A80452;
    address constant vaETH = 0xd1C117319B3595fbc39b471AB1fd485629eb05F2;
    address constant vspRewardToken = 0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421;
    address constant vspRewardControllerETH = 0x51EEf73abf5d4AC5F41De131591ed82c27a7Be3D;
    address constant vspRewardControllerDAI = 0x35864296944119F72AA1B468e13449222f3f0E67;
    address constant whitelistETHAddress = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;
    address constant whitelistUSDAddress = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    IVesperPool constant vesperPool = IVesperPool(vaETH);
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IAlchemistV2 alchemistETH;
    IAlchemistV2 alchemistUSD;
    IProxyAdmin proxyAdmin = IProxyAdmin(proxyAdminAddress);
    IWhitelist whitelistETH;
    IWhitelist whitelistUSD;

    AlchemixHarvester harvester;
    HarvestResolver resolver;
    AlchemistV2 newAlchemistV2;
    RewardCollectorVesper rewardCollectorVesper;
    RewardCollectorVesper rewardCollectorVesperUSD;
    VesperAdapterV1 adapterETH;
    VesperAdapterV1 adapterDAI;
    VesperAdapterV1 adapterUSDC;

    function setUp() external {
        alchemistETH = IAlchemistV2(alchemistETHAddress);
        alchemistUSD = IAlchemistV2(alchemistUSDAddress);
        whitelistETH = IWhitelist(whitelistETHAddress);
        whitelistUSD = IWhitelist(whitelistUSDAddress);

        newAlchemistV2 = new AlchemistV2();

        adapterETH = new VesperAdapterV1(AdapterInitializationParams({
            alchemist:       alchemistETHAddress,
            token:           address(vesperPool),
            underlyingToken: address(weth)
        }));

        adapterDAI = new VesperAdapterV1(AdapterInitializationParams({
            alchemist:       alchemistUSDAddress,
            token:           vaDAI,
            underlyingToken: DAI
        }));

        adapterUSDC = new VesperAdapterV1(AdapterInitializationParams({
            alchemist:       alchemistUSDAddress,
            token:           vaUSDC,
            underlyingToken: USDC
        }));

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapterETH),
            maximumLoss: 1,
            maximumExpectedValue: 10000000000000000 ether,
            creditUnlockBlocks: 7200
        });

        IAlchemistV2.YieldTokenConfig memory ytcDAI = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapterDAI),
            maximumLoss: 1,
            maximumExpectedValue: 10000000000000000 ether,
            creditUnlockBlocks: 7200
        });

        IAlchemistV2.YieldTokenConfig memory ytcUSDC = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapterUSDC),
            maximumLoss: 1,
            maximumExpectedValue: 10000000000000000 ether,
            creditUnlockBlocks: 7200
        });

        RewardcollectorParams memory rewardCollectorParams = RewardcollectorParams({
            alchemist:          alchemistETHAddress,
            debtToken:          alEthAddress,
            rewardToken:        vspRewardToken,
            swapRouter:         uniswapRouter
        });

        RewardcollectorParams memory rewardCollectorParamsUSD = RewardcollectorParams({
            alchemist:          alchemistUSDAddress,
            debtToken:          alUsdAddress,
            rewardToken:        vspRewardToken,
            swapRouter:         uniswapRouter
        });

        rewardCollectorVesper = new RewardCollectorVesper(rewardCollectorParams);
        rewardCollectorVesperUSD = new RewardCollectorVesper(rewardCollectorParamsUSD);

        hevm.startPrank(ADMIN);
        whitelistETH.add(address(this));
        whitelistETH.add(address(rewardCollectorVesper));
        whitelistUSD.add(address(this));
        whitelistUSD.add(address(0xbeef));
        whitelistUSD.add(address(rewardCollectorVesperUSD));
        alchemistETH.addYieldToken(address(vesperPool), ytc);
        alchemistETH.setYieldTokenEnabled(address(vesperPool), true);
        alchemistUSD.addYieldToken(vaDAI, ytcDAI);
        alchemistUSD.setYieldTokenEnabled(vaDAI, true);
        alchemistUSD.addYieldToken(vaUSDC, ytcUSDC);
        alchemistUSD.setYieldTokenEnabled(vaUSDC, true);
        proxyAdmin.upgrade(alchemistETHAddress, address(newAlchemistV2));
        proxyAdmin.upgrade(alchemistUSDAddress, address(newAlchemistV2));
        alchemistETH.setKeeper(address(rewardCollectorVesper), true);
        alchemistUSD.setKeeper(address(rewardCollectorVesperUSD), true);
        hevm.stopPrank();

        hevm.startPrank(address(rewardCollectorVesper));
        TokenUtils.safeApprove(vspRewardToken, uniswapRouter, 2**256 - 1);
        TokenUtils.safeApprove(alEthAddress, address(alchemistETH), 2**256 - 1);
        TokenUtils.safeApprove(address(weth), 0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e, 2**256 - 1);
        hevm.stopPrank();

        hevm.startPrank(address(rewardCollectorVesperUSD));
        TokenUtils.safeApprove(vspRewardToken, uniswapRouter, 2**256 - 1);
        TokenUtils.safeApprove(alUsdAddress, address(alchemistUSD), 2**256 - 1);
        TokenUtils.safeApprove(DAI, 0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c, 2**256 - 1);
        hevm.stopPrank();

        resolver = new HarvestResolver();
        harvester = new AlchemixHarvester(address(this), 100000e18, address(resolver));
        resolver.setHarvester(address(harvester), true);
        hevm.startPrank(ADMIN);
        alchemistUSD.setKeeper(address(harvester), true);
        alchemistETH.setKeeper(address(harvester), true);
        hevm.stopPrank();

        resolver.addHarvestJob(
            true,
            alchemistUSDAddress,
            address(0),
            address(vspRewardToken),
            vaDAI,
            0,
            0,
            100
        );

        resolver.addHarvestJob(
            true,
            alchemistUSDAddress,
            address(0),
            address(vspRewardToken),
            vaUSDC,
            0,
            0,
            100
        );

        resolver.addHarvestJob(
            true,
            alchemistETHAddress,
            address(0),
            address(vspRewardToken),
            vaETH,
            0,
            0,
            100
        );

        harvester.addRewardCollector(vaDAI, address(rewardCollectorVesperUSD));
        harvester.addRewardCollector(vaUSDC, address(rewardCollectorVesperUSD));
        harvester.addRewardCollector(vaETH, address(rewardCollectorVesper));
    }

    function testRoundTrip() external {
        deal(address(weth), address(this), 1e18);

        SafeERC20.safeApprove(address(weth), address(alchemistETH), 1e18);
        uint256 shares = alchemistETH.depositUnderlying(address(vesperPool), 1e18, address(this), 0);

        uint256 underlyingValue = shares * adapterETH.price() / 10**SafeERC20.expectDecimals(address(vesperPool));
        assertGt(underlyingValue, 1e18 * 9900 / BPS);
        
        SafeERC20.safeApprove(adapterETH.token(), address(adapterETH), shares);
        uint256 unwrapped = alchemistETH.withdrawUnderlying(address(vesperPool), shares, address(this), underlyingValue * 9900 / 10000);
        
        assertEq(weth.balanceOf(address(this)), unwrapped);
        assertEq(vesperPool.balanceOf(address(this)), 0);
        assertEq(vesperPool.balanceOf(address(adapterETH)), 0);
    }

    function testRoundTripFuzz(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(address(weth)) && 
            amount < type(uint96).max
        );
        
        deal(address(weth), address(this), amount);


        SafeERC20.safeApprove(address(weth), address(alchemistETH), amount);
        uint256 shares = alchemistETH.depositUnderlying(address(vesperPool), amount, address(this), 0);

        uint256 underlyingValue = shares * adapterETH.price() / 10**SafeERC20.expectDecimals(address(vesperPool));
        assertGt(underlyingValue, amount * 9900 / BPS);
        
        SafeERC20.safeApprove(adapterETH.token(), address(adapterETH), shares);
        uint256 unwrapped = alchemistETH.withdrawUnderlying(address(vesperPool), shares, address(this), underlyingValue * 9900 / 10000);
        
        assertEq(weth.balanceOf(address(this)), unwrapped);
        assertEq(vesperPool.balanceOf(address(this)), 0);
        assertEq(vesperPool.balanceOf(address(adapterETH)), 0);
    }

    function testRewardsETH() external {
        deal(address(weth), address(this), 100e18);

        SafeERC20.safeApprove(address(weth), address(alchemistETH), 100e18);
        alchemistETH.depositUnderlying(address(vesperPool), 100e18, address(this), 0);

        alchemistETH.mint(40e18, address(this));

        (int256 debtBefore, ) = alchemistETH.accounts(address((this)));

        hevm.warp(block.timestamp + 10000000000);
        hevm.roll(block.number + 10000000000);

        (address[] memory tokensDAI, uint256[] memory amountsWETH) = IVesperRewards(0x51EEf73abf5d4AC5F41De131591ed82c27a7Be3D).claimable(address(alchemistETHAddress));

        UniswapEstimatedPrice priceEstimator = new UniswapEstimatedPrice();

        uint256 wethRewardsExchange = priceEstimator.getExpectedExchange(uniSwapFactory, vspRewardToken, address(weth), uint24(3000), address(0), uint24(0), amountsWETH[0]);

        rewardCollectorVesper.claimAndDistributeRewards(address(vesperPool), wethRewardsExchange * 9900 / BPS);

        (int256 debtAfter, ) = alchemistETH.accounts(address((this)));
        assertGt(debtBefore, debtAfter);
    }

    function testRewardsETHFuzz(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(address(weth)) && 
            amount < type(uint96).max
        );

        deal(address(weth), address(this), amount);

        SafeERC20.safeApprove(address(weth), address(alchemistETH), amount);
        alchemistETH.depositUnderlying(address(vesperPool), amount, address(this), 0);

        (int256 debtBefore, ) = alchemistETH.accounts(address((this)));

        hevm.warp(block.timestamp + 10000000000);
        hevm.roll(block.number + 10000000000);
        
        rewardCollectorVesper.claimAndDistributeRewards(address(vesperPool), 0);

        (int256 debtAfter, ) = alchemistETH.accounts(address((this)));
        assertGt(debtBefore, debtAfter);
    }

    function testRewardsDAI() external {
        deal(address(DAI), address(this), 100e18);
        deal(address(USDC), address(this), 100e18);

        SafeERC20.safeApprove(DAI, address(alchemistUSD), 100e18);
        alchemistUSD.depositUnderlying(vaDAI, 100e18, address(this), 0);

        alchemistUSD.mint(40e18, address(this));

        (int256 debtBefore, ) = alchemistUSD.accounts(address((this)));

        hevm.warp(block.timestamp + 1000000);
        hevm.roll(block.number + 1000000);
        
        (address[] memory tokensDAI, uint256[] memory amountsDAI) = IVesperRewards(0x35864296944119F72AA1B468e13449222f3f0E67).claimable(address(alchemistUSDAddress));

        UniswapEstimatedPrice priceEstimator = new UniswapEstimatedPrice();

        uint256 daiRewardsExchange = priceEstimator.getExpectedExchange(uniSwapFactory, vspRewardToken, address(weth), uint24(3000), DAI, uint24(3000), amountsDAI[0]);

        rewardCollectorVesperUSD.claimAndDistributeRewards(vaDAI, daiRewardsExchange * 9900 / BPS);

        (int256 debtAfter, ) = alchemistUSD.accounts(address((this)));
        assertGt(debtBefore, debtAfter);
    }

    function testRewardsUSDC() external {
        deal(address(DAI), address(this), 100e18);
        deal(address(USDC), address(this), 100e18);

        SafeERC20.safeApprove(USDC, address(alchemistUSD), 100e18);
        alchemistUSD.depositUnderlying(vaUSDC, 100e18, address(this), 0);

        alchemistUSD.mint(40e18, address(this));

        (int256 debtBefore, ) = alchemistUSD.accounts(address((this)));

        hevm.warp(block.timestamp + 1000000);
        hevm.roll(block.number + 1000000);
        
        rewardCollectorVesperUSD.claimAndDistributeRewards(vaUSDC, 0);

        (int256 debtAfter, ) = alchemistUSD.accounts(address((this)));
        assertGt(debtBefore, debtAfter);
    }

    function testRewardsBothUSD() external {
        deal(address(DAI), address(this), 100e18);
        deal(address(USDC), address(this), 100e18);

        SafeERC20.safeApprove(DAI, address(alchemistUSD), 100e18);
        alchemistUSD.depositUnderlying(vaDAI, 100e18, address(this), 0);

        SafeERC20.safeApprove(USDC, address(alchemistUSD), 100e18);
        alchemistUSD.depositUnderlying(vaUSDC, 100e18, address(this), 0);

        alchemistUSD.mint(40e18, address(this));

        (int256 debtBefore, ) = alchemistUSD.accounts(address((this)));

        hevm.warp(block.timestamp + 1000000);
        hevm.roll(block.number + 1000000);
        
        rewardCollectorVesperUSD.claimAndDistributeRewards(vaDAI, 0);
        rewardCollectorVesperUSD.claimAndDistributeRewards(vaUSDC, 0);

        (int256 debtAfter, ) = alchemistUSD.accounts(address((this)));
        assertGt(debtBefore, debtAfter);
    }

    function testRewardsUSDFuzz(uint256 amountDAI, uint256 amountUSDC) external {
        hevm.assume(
            amountDAI >= 10**SafeERC20.expectDecimals(address(weth)) && 
            amountDAI < type(uint96).max
        );

        hevm.assume(
            amountUSDC >= 10**SafeERC20.expectDecimals(address(USDC)) && 
            amountUSDC < type(uint96).max
        );

        deal(address(DAI), address(this), amountDAI);
        deal(address(USDC), address(this), amountUSDC);

        SafeERC20.safeApprove(DAI, address(alchemistUSD), amountDAI);
        alchemistUSD.depositUnderlying(vaDAI, amountDAI, address(this), 0);

        SafeERC20.safeApprove(USDC, address(alchemistUSD), amountUSDC);
        alchemistUSD.depositUnderlying(vaUSDC, amountUSDC, address(this), 0);

        (int256 debtBefore, ) = alchemistUSD.accounts(address((this)));

        hevm.warp(block.timestamp + 1000000);
        hevm.roll(block.number + 1000000);

        rewardCollectorVesperUSD.claimAndDistributeRewards(vaDAI, 0);
        rewardCollectorVesperUSD.claimAndDistributeRewards(vaUSDC, 0);

        (int256 debtAfter, ) = alchemistUSD.accounts(address((this)));
        assertGt(debtBefore, debtAfter);
    }

    function testRewardsDAIWithHarvester() external {
        deal(address(DAI), address(this), 10000000000e18);

        SafeERC20.safeApprove(DAI, address(alchemistUSD), 20000000e18);
        alchemistUSD.depositUnderlying(vaDAI, 10000000e18, address(this), 0);

        alchemistUSD.mint(40e18, address(this));

        (int256 debtBefore, ) = alchemistUSD.accounts(address((this)));

        hevm.warp(block.timestamp + 30 days);
        hevm.roll(block.number + 10000000);

        deal(address(DAI), address(vaDAI), 10000000000e18);
        
        (bool canExec, bytes memory execPayload) = resolver.checker();
        (address alch, address yield, uint256 minOut, uint256 expectedExchange) = abi.decode(extractCalldata(execPayload), (address, address, uint256, uint256));

        if (canExec == true) {
            harvester.harvest(alch, yield, minOut, expectedExchange);
        }

        (int256 debtAfter, ) = alchemistUSD.accounts(address((this)));
        assertGt(debtBefore, debtAfter);
    }


    function testRewardsUSDCWithHarvester() external {
        deal(address(USDC), address(this), 10000000000e18);

        SafeERC20.safeApprove(USDC, address(alchemistUSD), 20000000e18);
        alchemistUSD.depositUnderlying(vaUSDC, 10000000e18, address(this), 0);

        alchemistUSD.mint(40e18, address(this));

        (int256 debtBefore, ) = alchemistUSD.accounts(address((this)));

        hevm.warp(block.timestamp + 30 days);
        hevm.roll(block.number + 10000000);

        deal(address(USDC), address(vaUSDC), 10000000000e18);
        
        (bool canExec, bytes memory execPayload) = resolver.checker();
        (address alch, address yield, uint256 minOut, uint256 expectedExchange) = abi.decode(extractCalldata(execPayload), (address, address, uint256, uint256));

        if (canExec == true) {
            harvester.harvest(alch, yield, minOut, expectedExchange);
        }

        (int256 debtAfter, ) = alchemistUSD.accounts(address((this)));
        assertGt(debtBefore, debtAfter);
    }

    function testRewardsETHWithHarvester() external {
        deal(address(weth), address(this), 10000000000e18);

        SafeERC20.safeApprove(address(weth), address(alchemistETH), 20000000e18);
        alchemistETH.depositUnderlying(vaETH, 10000000e18, address(this), 0);

        alchemistETH.mint(40e18, address(this));

        (int256 debtBefore, ) = alchemistETH.accounts(address((this)));

        hevm.warp(block.timestamp + 30 days);
        hevm.roll(block.number + 10000000);

        deal(address(weth), address(vaETH), 10000000000e18);
        
        (bool canExec, bytes memory execPayload) = resolver.checker();
        (address alch, address yield, uint256 minOut, uint256 expectedExchange) = abi.decode(extractCalldata(execPayload), (address, address, uint256, uint256));

        if (canExec == true) {
            harvester.harvest(alch, yield, minOut, expectedExchange);
        }

        (int256 debtAfter, ) = alchemistETH.accounts(address((this)));
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
}