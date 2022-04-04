// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {stdCheats} from "forge-std/stdlib.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {
    YearnStETHCurveAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/yearn/YearnStETHCurveAdapterV1.sol";

import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IStableSwap2Pool} from "../interfaces/external/curve/IStableSwap2Pool.sol";
import {IYearnVaultV2} from "../interfaces/external/yearn/IYearnVaultV2.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

contract YearnStETHCurveAdapterV1Test is DSTestPlus, stdCheats {
    IYearnVaultV2 constant vault = IYearnVaultV2(0xdCD90C7f6324cfa40d7169ef80b12031770B4325);
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IStableSwap2Pool constant curvePool = IStableSwap2Pool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IERC20 constant curvePoolToken = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);

    YearnStETHCurveAdapterV1 adapter;

    function setUp() external {
        adapter = new YearnStETHCurveAdapterV1(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(vault),
            underlyingToken: address(weth),
            curvePool:       address(curvePool),
            curvePoolToken:  address(curvePoolToken),
            ethPoolIndex:    0,
            stEthPoolIndex:  1
        }));
    }

    function testWrap() external {
        tip(address(weth), address(this), 1e18);

        SafeERC20.safeApprove(address(weth), address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(0xbeef));

        assertEq(weth.allowance(address(this), address(adapter)), 0);
        assertEq(vault.balanceOf(address(0xbeef)), wrapped);
    }

    function testUnwrap() external {
        tip(address(vault), address(this), 1e18);

        SafeERC20.safeApprove(address(vault), address(adapter), 1e18);
        uint256 unwrapped = adapter.unwrap(1e18, address(0xbeef));

        assertEq(vault.allowance(address(this), address(adapter)), 0);
        assertEq(weth.balanceOf(address(0xbeef)), unwrapped);
    }
}