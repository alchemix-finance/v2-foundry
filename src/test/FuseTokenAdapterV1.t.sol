// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";

import {
    FuseTokenAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/fuse/FuseTokenAdapterV1.sol";

import {ICERC20} from "../interfaces/external/compound/ICERC20.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {LibFuse} from "../libraries/LibFuse.sol";

contract FuseTokenAdapterV1Test is DSTestPlus, stdCheats {
    uint256 constant BPS = 10000;
    ICERC20 constant fDAI = ICERC20(0x7e9cE3CAa9910cc048590801e64174957Ed41d43);

    IERC20 underlyingToken;
    FuseTokenAdapterV1 adapter;

    function setUp() external {
        underlyingToken = IERC20(fDAI.underlying());

        adapter = new FuseTokenAdapterV1(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(fDAI),
            underlyingToken: address(fDAI.underlying())
        }));
    }

    function testRoundTrip() external {
        tip(address(underlyingToken), address(this), 1e18);

        SafeERC20.safeApprove(address(underlyingToken), address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(fDAI));
        assertGt(underlyingValue, 1e18 * 9900 / BPS /* 1% slippage */);

        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));

        assertEq(underlyingToken.balanceOf(address(0xbeef)), unwrapped);
        assertEq(fDAI.balanceOf(address(this)), 0);
        assertEq(fDAI.balanceOf(address(adapter)), 0);
    }

    function testRoundTrip(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(adapter.underlyingToken()) && 
            amount < type(uint96).max
        );
        
        tip(address(underlyingToken), address(this), amount);

        SafeERC20.safeApprove(address(underlyingToken), address(adapter), amount);
        uint256 wrapped = adapter.wrap(amount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(fDAI));
        assertGt(underlyingValue, amount * 9900 / BPS /* 1% slippage */);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));

        assertEq(underlyingToken.balanceOf(address(0xbeef)), unwrapped);
        assertEq(fDAI.balanceOf(address(this)), 0);
        assertEq(fDAI.balanceOf(address(adapter)), 0);
    }
}