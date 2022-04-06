// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import "forge-std/console.sol";

import {
    VesperAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/vesper/VesperAdapterV1.sol";

import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IVesperPool} from "../interfaces/external/vesper/IVesperPool.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract VesperAdapterV1Test is DSTestPlus, stdCheats {
    IVesperPool constant vesperPool = IVesperPool(0xcA0c34A3F35520B9490C1d58b35A19AB64014D80);
    VesperAdapterV1 adapter;

    function setUp() external {
        adapter = new VesperAdapterV1(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(0xcA0c34A3F35520B9490C1d58b35A19AB64014D80),
            underlyingToken: address(0x6B175474E89094C44Da98b954EedeAC495271d0F)
        }));

        console.log(adapter.token());
    }

    function testPrice() external {
        assertEq(adapter.price(), vesperPool.getPricePerShare());
    }

    function testWrap() external {
        tip(adapter.underlyingToken(), address(this), 1e18);

        SafeERC20.safeApprove(adapter.underlyingToken(), address(adapter), 1e18);

        uint256 wrapped = adapter.wrap(1e18, address(0xbeef));

        assertApproxEq(1e18, (wrapped * adapter.price()) / 1e18, 100);
    }

    function testUnwrap() external {
        tip(adapter.token(), address(this), 1e18);

        SafeERC20.safeApprove(adapter.token(), address(adapter), 1e18);

        uint256 unWrapped = adapter.unwrap(1e18, address(0xbeef));
        
        assertApproxEq(1e18 , (unWrapped * 1e36) / (1e18 * adapter.price()), 2e16);
    }
}