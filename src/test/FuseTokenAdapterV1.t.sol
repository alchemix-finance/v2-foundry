// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import "forge-std/console.sol";

import {
    FuseTokenAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/Fuse/FuseTokenAdapterV1.sol";

import {ICERC20} from "../interfaces/external/compound/ICERC20.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {LibFuse} from "../libraries/LibFuse.sol";

contract FuseTokenAdapterV1Test is DSTestPlus, stdCheats {
    FuseTokenAdapterV1 adapter;

    function setUp() external {
        ICERC20 fDAI = ICERC20(0x7e9cE3CAa9910cc048590801e64174957Ed41d43);

        adapter = new FuseTokenAdapterV1(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(fDAI),
            underlyingToken: address(fDAI.underlying())
        }));

        console.log(adapter.token());
    }

    function testPrice() external {
        console.log(adapter.price());
        console.log(adapter.underlyingToken());
    }

    function testWrap() external {
        tip(address(adapter.underlyingToken()), address(this), 1e18);

        SafeERC20.safeApprove(adapter.underlyingToken(), address(adapter), 1e18);

        uint256 wrapped = adapter.wrap(1e18, address(0xbeef));

        assertApproxEq(1e18 , wrapped * adapter.price() / 1e18, 1e10);
    }

    function testUnwrap() external {
        tip(adapter.token(), address(this), 1e18);

        SafeERC20.safeApprove(adapter.token(), address(adapter), 1e18);

        uint256 unwrapped = adapter.unwrap(1e18, address(0xbeef));
        
        assertApproxEq(adapter.price() , unwrapped, 1e10);
    }
}