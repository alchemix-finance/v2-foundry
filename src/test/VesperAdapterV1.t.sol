// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    VesperAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/vesper/VesperAdapterV1.sol";

import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IVesperPool} from "../interfaces/external/vesper/IVesperPool.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract VesperAdapterV1Test is DSTestPlus {
    uint256 constant BPS = 10000;
    IVesperPool constant vesperPool = IVesperPool(0xd1C117319B3595fbc39b471AB1fd485629eb05F2);
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    VesperAdapterV1 adapter;

    function setUp() external {
        adapter = new VesperAdapterV1(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(vesperPool),
            underlyingToken: address(weth)
        }));
    }

    function testRoundTrip() external {
        tip(address(weth), address(this), 1e18);

        SafeERC20.safeApprove(address(weth), address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(vesperPool));
        assertGt(underlyingValue, 1e18 * 9900 / BPS);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(weth.balanceOf(address(0xbeef)), unwrapped);
        assertEq(vesperPool.balanceOf(address(this)), 0);
        assertEq(vesperPool.balanceOf(address(adapter)), 0);
    }

    function testRoundTrip(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(address(weth)) && 
            amount < type(uint96).max
        );
        
        tip(address(weth), address(this), amount);

        SafeERC20.safeApprove(address(weth), address(adapter), amount);
        uint256 wrapped = adapter.wrap(amount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(vesperPool));
        assertGt(underlyingValue, amount * 9900 / BPS);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(weth.balanceOf(address(0xbeef)), unwrapped);
        assertEq(vesperPool.balanceOf(address(this)), 0);
        assertEq(vesperPool.balanceOf(address(adapter)), 0);
    }
}