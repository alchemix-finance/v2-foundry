// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    WstETHAdapterOptimism,
    InitializationParams as AdapterInitializationParams
} from "../adapters/lido/WstETHAdapterOptimism.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IChainlinkOracle} from "../interfaces/external/chainlink/IChainlinkOracle.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IStableSwap2Pool} from "../interfaces/external/curve/IStableSwap2Pool.sol";
import {IStETH} from "../interfaces/external/lido/IStETH.sol";
import {IWstETH} from "../interfaces/external/lido/IWstETH.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract WstETHAdapterOptimismTest is DSTestPlus {
    uint256 constant BPS = 10000;
    address constant admin = 0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a;
    address constant whitelistETHAddress = 0xc5fE32e46fD226364BFf7A035e8Ca2aBE390a68f;

    IAlchemistV2 constant alchemist = IAlchemistV2(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4);
    IChainlinkOracle constant oracleStethEth = IChainlinkOracle(0x524299Ab0987a7c4B3c8022a35669DdcdC715a10);
    IWstETH constant wstETH = IWstETH(0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb);
    IWETH9 constant weth = IWETH9(0x4200000000000000000000000000000000000006);

    WstETHAdapterOptimism adapter;

    function setUp() external {
        adapter = new WstETHAdapterOptimism(AdapterInitializationParams({
            alchemist:       address(alchemist),
            token:           address(wstETH),
            underlyingToken: address(weth),
            velodromeRouter: 0x9c12939390052919aF3155f41Bf4160Fd3666A6f,
            oracleWstethEth:  address(oracleStethEth),
            referral:        address(0)
        }));

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });

        hevm.startPrank(admin);
        alchemist.addYieldToken(address(wstETH), ytc);
        alchemist.setYieldTokenEnabled(address(wstETH), true);
        IWhitelist(whitelistETHAddress).add(address(this));
        alchemist.setMaximumExpectedValue(address(wstETH), 1000000000e18);
        hevm.stopPrank();
    }

    function testRoundTrip() external {
        deal(address(weth), address(this), 1e18);
        
        uint256 startingBalance = wstETH.balanceOf(address(alchemist));

        SafeERC20.safeApprove(address(weth), address(alchemist), 1e18);
        uint256 shares = alchemist.depositUnderlying(address(wstETH), 1e18, address(this), 0);

        // Test that price function returns value within 0.1% of actual
        uint256 underlyingValue = shares * adapter.price() / 10**SafeERC20.expectDecimals(address(wstETH));
        assertGt(underlyingValue, 1e18 * 9900 / BPS);
        
        uint256 unwrapped = alchemist.withdrawUnderlying(address(wstETH), shares, address(this), shares * 9990 / 10000);

        uint256 endBalance = wstETH.balanceOf(address(alchemist));
        
        assertEq(weth.balanceOf(address(this)), unwrapped);
        assertEq(wstETH.balanceOf(address(this)), 0);
        assertEq(wstETH.balanceOf(address(adapter)), 0);
        assertApproxEq(endBalance - startingBalance, 0, 10);
    }
}