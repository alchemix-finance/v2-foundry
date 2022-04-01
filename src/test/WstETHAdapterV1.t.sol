// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "forge-std/stdlib.sol";

import {
    WstETHAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/lido/WstETHAdapterV1.sol";

import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IStableSwap2Pool} from "../interfaces/external/curve/IStableSwap2Pool.sol";
import {IStETH} from "../interfaces/external/lido/IStETH.sol";
import {IWstETH} from "../interfaces/external/lido/IWstETH.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract WstETHAdapterV1Test is DSTestPlus, stdCheats {
    IStETH constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IStableSwap2Pool constant curvePool = IStableSwap2Pool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    WstETHAdapterV1 adapter;

    function setUp() external {
        adapter = new WstETHAdapterV1(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(wstETH),
            parentToken:     address(stETH),
            underlyingToken: address(weth),
            curvePool:       address(curvePool),
            ethPoolIndex:    0,
            stEthPoolIndex:  1,
            referral:        address(0)
        }));
    }

    function testPrice() external {
        uint256 decimals = SafeERC20.expectDecimals(address(wstETH));
        assertEq(adapter.price(), stETH.getPooledEthByShares(10**decimals));
    }

    function testWrap() external {
        tip(address(weth), address(this), 1e18);

        SafeERC20.safeApprove(address(weth), address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(0xbeef));

        assertEq(weth.allowance(address(this), address(adapter)), 0);
        assertEq(wstETH.balanceOf(address(0xbeef)), wrapped);
    }

    function testUnwrap() external {
        tip(address(wstETH), address(this), 1e18);

        SafeERC20.safeApprove(address(wstETH), address(adapter), 1e18);
        uint256 unwrapped = adapter.unwrap(1e18, address(0xbeef));

        assertEq(wstETH.allowance(address(this), address(adapter)), 0);
        assertEq(weth.balanceOf(address(0xbeef)), unwrapped);
    }
}