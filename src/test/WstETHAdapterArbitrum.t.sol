// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    WstETHAdapterArbitrum,
    InitializationParams as AdapterInitializationParams
} from "../adapters/lido/WstETHAdapterArbitrum.sol";

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
    address constant admin = 0x886FF7a2d46dcc2276e2fD631957969441130847;
    address constant whitelistETHAddress = 0x6996b41c369D3175F18D16ba14952F8C89665710;

    IAlchemistV2 constant alchemist = IAlchemistV2(0x654e16a0b161b150F5d1C8a5ba6E7A7B7760703A);
    IChainlinkOracle constant oracleWStethEth = IChainlinkOracle(0xb523AE262D20A936BC152e6023996e46FDC2A95D);
    IWstETH constant wstETH = IWstETH(0x5979D7b546E38E414F7E9822514be443A4800529);
    IWETH9 constant weth = IWETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    WstETHAdapterArbitrum adapter;

    function setUp() external {
        adapter = new WstETHAdapterArbitrum(AdapterInitializationParams({
            alchemist:       address(alchemist),
            token:           address(wstETH),
            underlyingToken: address(weth),
            balancerVault:   0xBA12222222228d8Ba445958a75a0704d566BF2C8,
            oracleWstethEth: address(oracleWStethEth)
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