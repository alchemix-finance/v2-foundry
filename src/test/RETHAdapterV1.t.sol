// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import "forge-std/console.sol";

import {
    RETHAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/rocket/RETHAdapterV1.sol";

import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IRETH} from "../interfaces/external/rocket/IRETH.sol";
import {IRocketStorage} from "../interfaces/external/rocket/IRocketStorage.sol";

import {RocketPool} from "../libraries/RocketPool.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";

contract RocketStakedEthereumAdapterV1Test is DSTestPlus, stdCheats {
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IRocketStorage constant rocketStorage = IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);

    IRETH rETH;
    RETHAdapterV1 adapter;

    function setUp() external {
        rETH = RocketPool.getRETH(rocketStorage);

        adapter = new RETHAdapterV1(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(rETH),
            underlyingToken: address(weth)
        }));
    }

    function testPrice() external {
        uint256 decimals = SafeERC20.expectDecimals(address(rETH));
        assertEq(adapter.price(), rETH.getEthValue(10**decimals));
    }

    function testWrap() external {
        tip(address(weth), address(this), 1e18);

        SafeERC20.safeApprove(address(weth), address(adapter), 1e18);

        expectUnsupportedOperationError("Wrapping is not supported");
        adapter.wrap(1e18, address(0xbeef));
    }

    function testUnwrap() external {
        tip(address(rETH), address(this), 1e18);

        uint256 expectedEth = rETH.getEthValue(1e18);

        SafeERC20.safeApprove(address(rETH), address(adapter), 1e18);
        uint256 unwrapped = adapter.unwrap(1e18, address(0xbeef));
        
        assertEq(rETH.allowance(address(this), address(adapter)), 0);
        assertEq(weth.balanceOf(address(0xbeef)), unwrapped);
        assertEq(weth.balanceOf(address(0xbeef)), expectedEth);
    }
}