// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    FraxEthAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/frax/FraxEthAdapter.sol";

import {ICERC20} from "../interfaces/external/compound/ICERC20.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {LibFuse} from "../libraries/LibFuse.sol";

contract FraxEthAdapterTest is DSTestPlus {
    uint256 constant BPS = 10000;
    address constant frxEth = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant sfrxEth = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    FraxEthAdapter adapter;

    function setUp() external {
        adapter = new FraxEthAdapter(AdapterInitializationParams({
            stakingToken:    address(this),
            token:           frxEth,
            underlyingToken: 
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