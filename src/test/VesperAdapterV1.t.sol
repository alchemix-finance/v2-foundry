// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {AlchemistV2} from "../AlchemistV2.sol";
import {
    RewardCollectorVesper,
    InitializationParams as RewardcollectorParams
} from "../utils/RewardCollectorVesper.sol";

import {
    VesperAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/vesper/VesperAdapterV1.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IProxyAdmin} from "../interfaces/external/IProxyAdmin.sol";
import {IVesperPool} from "../interfaces/external/vesper/IVesperPool.sol";
import {IVesperRewards} from "../interfaces/external/vesper/IVesperRewards.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract VesperAdapterV1Test is DSTestPlus {
    uint256 constant BPS = 10000;
    address constant ADMIN = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant alEthAddress = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant alchemistETHAddress = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant proxyAdminAddress = 0xE0fC5CB7665041CdA26969A2D1ceb5cD5046347d;
    address constant uniswapRouter = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant vspRewardToken = 0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421;
    address constant vspRewardController = 0x51EEf73abf5d4AC5F41De131591ed82c27a7Be3D;
    address constant whitelistETHAddress = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;
    IVesperPool constant vesperPool = IVesperPool(0xd1C117319B3595fbc39b471AB1fd485629eb05F2);
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IAlchemistV2 alchemist;
    IProxyAdmin proxyAdmin = IProxyAdmin(proxyAdminAddress);
    IWhitelist whitelist;

    AlchemistV2 newAlchemistV2;
    RewardCollectorVesper rewardCollectorVesper;
    VesperAdapterV1 adapter;

    function setUp() external {
        alchemist = IAlchemistV2(alchemistETHAddress);
        whitelist = IWhitelist(whitelistETHAddress);

        newAlchemistV2 = new AlchemistV2();

        adapter = new VesperAdapterV1(AdapterInitializationParams({
            alchemist:       alchemistETHAddress,
            token:           address(vesperPool),
            underlyingToken: address(weth)
        }));

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
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

        rewardCollectorVesper = new RewardCollectorVesper(rewardCollectorParams);

        hevm.startPrank(ADMIN);
        whitelist.add(address(this));
        alchemist.addYieldToken(address(vesperPool), ytc);
        alchemist.setYieldTokenEnabled(address(vesperPool), true);
        proxyAdmin.upgrade(alchemistETHAddress, address(newAlchemistV2));
        alchemist.setKeeper(address(rewardCollectorVesper), true);
        hevm.stopPrank();
    }

    function testRoundTrip() external {
        deal(address(weth), address(this), 1e18);

        SafeERC20.safeApprove(address(weth), address(alchemist), 1e18);
        uint256 shares = alchemist.depositUnderlying(address(vesperPool), 1e18, address(this), 0);

        uint256 underlyingValue = shares * adapter.price() / 10**SafeERC20.expectDecimals(address(vesperPool));
        assertGt(underlyingValue, 1e18 * 9900 / BPS);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), shares);
        uint256 unwrapped = alchemist.withdrawUnderlying(address(vesperPool), shares, address(this), underlyingValue * 9900 / 10000);
        
        assertEq(weth.balanceOf(address(this)), unwrapped);
        assertEq(vesperPool.balanceOf(address(this)), 0);
        assertEq(vesperPool.balanceOf(address(adapter)), 0);
    }

    function testRoundTripFuzz(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(address(weth)) && 
            amount < type(uint96).max
        );
        
        deal(address(weth), address(this), amount);


        SafeERC20.safeApprove(address(weth), address(alchemist), amount);
        uint256 shares = alchemist.depositUnderlying(address(vesperPool), amount, address(this), 0);

        uint256 underlyingValue = shares * adapter.price() / 10**SafeERC20.expectDecimals(address(vesperPool));
        assertGt(underlyingValue, amount * 9900 / BPS);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), shares);
        uint256 unwrapped = alchemist.withdrawUnderlying(address(vesperPool), shares, address(this), underlyingValue * 9900 / 10000);
        
        assertEq(weth.balanceOf(address(this)), unwrapped);
        assertEq(vesperPool.balanceOf(address(this)), 0);
        assertEq(vesperPool.balanceOf(address(adapter)), 0);
    }

    function testRewards() external {
        deal(address(weth), address(this), 100e18);

        SafeERC20.safeApprove(address(weth), address(alchemist), 100e18);
        alchemist.depositUnderlying(address(vesperPool), 100e18, address(this), 0);

        alchemist.mint(40e18, address(this));

        (int256 debtBefore, ) = alchemist.accounts(address((this)));

        hevm.warp(block.timestamp + 10000);
        hevm.roll(block.number + 10000);
        
        address[] memory assets = new address[](1);
        assets[0] = address(vesperPool);
        rewardCollectorVesper.claimAndDistributeRewards(assets, 0);

        (int256 debtAfter, ) = alchemist.accounts(address((this)));
        assertGt(debtAfter, debtBefore);
    }
}