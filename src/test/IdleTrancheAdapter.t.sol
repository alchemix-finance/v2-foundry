// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import "../adapters/idle/IdleTrancheAdapter.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

interface GuardedLaunchUpgradable {
    function owner() external view returns (address);

    /// @notice TVL limit in underlying value
    function limit() external view returns (uint256);

    /// @notice set contract TVL limit
    /// @param _limit limit in underlying value, 0 means no limit
    function _setLimit(uint256 _limit) external;
}

contract IdleTrancheAdapterTest is DSTestPlus {
    /// @notice Idle.finance: Clearpool cpWIN-USDC AA/BB
    IIdleCDO constant idleCDO = IIdleCDO(0xDBCEE5AE2E9DAf0F5d93473e08780C9f45DfEb93);
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

    IdleTrancheAdapter adapter;
    address token;
    address underlying;

    function setUp() external {
        underlying = USDC;
        token = idleCDO.AATranche();
        adapter = new IdleTrancheAdapter(token, underlying, address(idleCDO));

        // set limit to max
        vm.prank(GuardedLaunchUpgradable(address(idleCDO)).owner());
        GuardedLaunchUpgradable(address(idleCDO))._setLimit(type(uint256).max);

        vm.label(underlying, "underlying");
        vm.label(token, "token");
        vm.label(address(idleCDO), "idleCDO");
    }

    function testPrice() external {
        assertEq(adapter.price(), idleCDO.virtualPrice(token));
    }

    function testWrap() external {
        deal(underlying, address(this), 1e18);

        SafeERC20.safeApprove(underlying, address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(0xbeef));

        assertEq(IERC20(underlying).allowance(address(this), address(adapter)), 0);
        assertEq(IERC20(token).balanceOf(address(0xbeef)), wrapped);
    }

    function testUnwrap() external {
        deal(token, address(this), 1e18);

        SafeERC20.safeApprove(token, address(adapter), 1e18);
        uint256 unwrapped = adapter.unwrap(1e18, address(0xbeef));

        assertEq(IERC20(token).allowance(address(this), address(adapter)), 0);
        assertEq(IERC20(underlying).balanceOf(address(0xbeef)), unwrapped);
    }

    function testWrapGrief() external {
        deal(underlying, address(this), 1e18);
        deal(token, address(adapter), 1e18);

        SafeERC20.safeApprove(underlying, address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(0xbeef));

        assertEq(IERC20(underlying).allowance(address(this), address(adapter)), 0);
        assertEq(IERC20(token).balanceOf(address(0xbeef)), wrapped);
    }
}
