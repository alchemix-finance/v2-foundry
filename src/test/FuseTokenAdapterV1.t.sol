// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import "forge-std/console.sol";

import {
    FuseTokenAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/fuse/FuseTokenAdapterV1.sol";

import {ICERC20} from "../interfaces/external/compound/ICERC20.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {LibFuse} from "../libraries/LibFuse.sol";

contract FuseTokenAdapterV1Test is DSTestPlus, stdCheats {
    ICERC20 fDAI = ICERC20(0x7e9cE3CAa9910cc048590801e64174957Ed41d43);
    FuseTokenAdapterV1 adapter;

    uint256 constant BPS = 10000;

    function setUp() external {
        adapter = new FuseTokenAdapterV1(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(fDAI),
            underlyingToken: address(fDAI.underlying())
        }));

        console.log(adapter.token());
    }

    function testPrice() external {
        assertApproxEq(adapter.price(), fDAI.exchangeRateStored(), 1e14);
    }

    function testUnwrap() external {
        uint256 amount = 1e18;

        tip(adapter.underlyingToken(), address(this), amount);

        SafeERC20.safeApprove(adapter.underlyingToken(), address(adapter), amount);

        uint256 wrapped = adapter.wrap(amount, address(this));

        assertGt(wrapped * adapter.price(), (amount * 9900 / BPS));
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);

        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));

        assertGt(unwrapped, amount * 9900 / BPS);
        assertGt(IERC20(adapter.underlyingToken()).balanceOf(address(0xbeef)), amount * 9900 / BPS);
    }

    function testUnwrap(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(adapter.underlyingToken()) && 
            amount < type(uint96).max
        );
        
        tip(adapter.underlyingToken(), address(this), amount);

        SafeERC20.safeApprove(adapter.underlyingToken(), address(adapter), amount);

        uint256 wrapped = adapter.wrap(amount, address(this));

        assertGt(wrapped * adapter.price(), (amount * 9900 / BPS));
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);

        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertGt(unwrapped, amount * 9900 / BPS);
        assertGt(IERC20(adapter.underlyingToken()).balanceOf(address(0xbeef)), amount * 9900 / BPS);
    }
}