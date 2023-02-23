// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {AlchemistV2} from "../AlchemistV2.sol";
import {AlchemixHarvester} from "../keepers/AlchemixHarvester.sol";
import {HarvestResolver} from "../keepers/HarvestResolver.sol";
import {TransmuterV2} from "../TransmuterV2.sol";
import {Whitelist} from "../utils/Whitelist.sol";

import {
    AAVETokenAdapter,
    InitializationParams as AdapterInitializationParamsAave
} from "../adapters/aave/AAVETokenAdapter.sol";

import {
    RewardCollectorVesper,
    InitializationParams as RewardcollectorParamsVesper
} from "../utils/RewardCollectorVesper.sol";


import {UniswapEstimatedPrice} from "../utils/UniswapEstimatedPrice.sol";

import {
    VesperAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/vesper/VesperAdapterV1.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {ILendingPool} from "../interfaces/external/aave/ILendingPool.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IProxyAdmin} from "../interfaces/external/IProxyAdmin.sol";
import {ISwapRouter} from "../interfaces/external/uniswap/ISwapRouter.sol";
import {StaticAToken} from "../external/aave/StaticAToken.sol";
import {ITransmuterBuffer} from "../interfaces/transmuter/ITransmuterBuffer.sol";
import {IUniswapV3Factory} from "../interfaces/external/uniswap/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../interfaces/external/uniswap/IUniswapV3Pool.sol";
import {IVesperPool} from "../interfaces/external/vesper/IVesperPool.sol";
import {IVesperRewards} from "../interfaces/external/vesper/IVesperRewards.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract FraxStrategyTest is DSTestPlus {
    uint256 constant BPS = 10000;
    address constant ADMIN = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant alUsdAddress = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address constant alchemistUSDAddress =0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant frax = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address constant proxyAdminAddress = 0xE0fC5CB7665041CdA26969A2D1ceb5cD5046347d;
    address constant uniSwapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant uniswapRouter = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant vaFrax = 0xc14900dFB1Aa54e7674e1eCf9ce02b3b35157ba5;
    address constant vspRewardToken = 0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421;
    address constant vspRewardControllerETH = 0x51EEf73abf5d4AC5F41De131591ed82c27a7Be3D;
    address constant vspRewardControllerDAI = 0x35864296944119F72AA1B468e13449222f3f0E67;
    address constant whitelistETHAddress = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;
    address constant whitelistUSDAddress = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IAlchemistV2 alchemistUSD;
    IProxyAdmin proxyAdmin = IProxyAdmin(proxyAdminAddress);
    IWhitelist whitelistUSD;

    AlchemixHarvester harvester;
    HarvestResolver resolver;
    AlchemistV2 newAlchemistV2;
    AAVETokenAdapter adapter;
    RewardCollectorVesper rewardCollectorVesperUSD;
    VesperAdapterV1 adapterFrax;
    StaticAToken staticAToken;

    function setUp() external {
        alchemistUSD = IAlchemistV2(alchemistUSDAddress);
        whitelistUSD = IWhitelist(whitelistUSDAddress);

        staticAToken = new StaticAToken(
            ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9),
            0xd4937682df3C8aEF4FE912A96A74121C0829E664,
            "Static Aave FRAX",
            "saFRAX"
        );
        
        adapter = new AAVETokenAdapter(AdapterInitializationParamsAave({
            alchemist:       address(this),
            token:           address(staticAToken),
            underlyingToken: address(frax)
        }));

        IAlchemistV2AdminActions.UnderlyingTokenConfig memory config = IAlchemistV2AdminActions.UnderlyingTokenConfig({
			repayLimitMinimum: 1,
			repayLimitMaximum: 1000,
			repayLimitBlocks: 10,
			liquidationLimitMinimum: 1,
			liquidationLimitMaximum: 1000,
			liquidationLimitBlocks: 7200
		});

        hevm.startPrank(ADMIN);
        whitelistUSD.add(address(this));
        whitelistUSD.add(address(0xbeef));
        alchemistUSD.addUnderlyingToken(frax, config);
        alchemistUSD.setUnderlyingTokenEnabled(frax, true);

        adapterFrax = new VesperAdapterV1(AdapterInitializationParams({
            alchemist:       alchemistUSDAddress,
            token:           vaFrax,
            underlyingToken: frax
        }));

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapterFrax),
            maximumLoss: 1,
            maximumExpectedValue: 10000000000000000 ether,
            creditUnlockBlocks: 7200
        });

        IAlchemistV2.YieldTokenConfig memory ytcAave = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 10000000000000000 ether,
            creditUnlockBlocks: 7200
        });

        alchemistUSD.addYieldToken(vaFrax, ytc);
        alchemistUSD.addYieldToken(address(staticAToken), ytcAave);
        alchemistUSD.setYieldTokenEnabled(vaFrax, true);
        alchemistUSD.setYieldTokenEnabled(address(staticAToken), true);

        hevm.stopPrank();
    }

    function testRoundTripVesperFrax() external {
        deal(address(frax), address(this), 100e6);

        SafeERC20.safeApprove(frax, address(alchemistUSD), 100e6);

        uint256 shares = alchemistUSD.depositUnderlying(vaFrax, 100e6, address(this), 0);

        uint256 underlyingValue = shares * adapterFrax.price() / 10**SafeERC20.expectDecimals(vaFrax);
        assertGt(underlyingValue, 100e6 * 9900 / BPS);
        
        SafeERC20.safeApprove(adapterFrax.token(), address(adapterFrax), shares);
        uint256 unwrapped = alchemistUSD.withdrawUnderlying(vaFrax, shares, address(this), underlyingValue * 9900 / 10000);   
        assertGt(unwrapped, 100e6 * 9900 / 10000);
    }

    function testRoundTripAave() external {
        uint256 depositAmount = 1e18;

        deal(frax, address(this), depositAmount);

        SafeERC20.safeApprove(frax, address(adapter), depositAmount);
        uint256 wrapped = adapter.wrap(depositAmount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(staticAToken));
        assertGe(depositAmount, underlyingValue);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(IERC20(frax).balanceOf(address(0xbeef)), unwrapped);
        assertEq(staticAToken.balanceOf(address(this)), 0);
        assertEq(staticAToken.balanceOf(address(adapter)), 0);
    }
}