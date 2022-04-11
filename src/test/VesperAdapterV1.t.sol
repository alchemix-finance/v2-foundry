// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

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

    uint256 constant BPS = 10000;

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

    function testUnwrap() external {
        uint256 amount = 1e18;

        tip(adapter.underlyingToken(), address(this), amount);

        SafeERC20.safeApprove(adapter.underlyingToken(), address(adapter), amount);

        uint256 wrapped = adapter.wrap(amount, address(this));

        assertGt(wrapped * adapter.price(), (amount * 9900 / BPS));
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);

        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertGt(unwrapped, amount * 9900 / BPS);
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
    }
}