// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";

import {
    AAVETokenAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/aave/AAVETokenAdapter.sol";

import {StaticAToken} from "../external/aave/StaticAToken.sol";
import {ILendingPool} from "../interfaces/external/aave/ILendingPool.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract AAVETokenAdapterTest is DSTestPlus, stdCheats {
    uint256 constant BPS = 10000;
    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // ETH mainnet DAI
    ILendingPool lendingPool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    address aToken = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    string wrappedTokenName = "staticAaveDai";
    string wrappedTokenSymbol = "saDAI";
    StaticAToken staticAToken;
    AAVETokenAdapter adapter;

    function setUp() external {
        staticAToken = new StaticAToken(
            lendingPool,
            aToken,
            wrappedTokenName,
            wrappedTokenSymbol
        );
        adapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(staticAToken),
            underlyingToken: address(dai)
        }));
    }

    function testRoundTrip() external {
        tip(dai, address(this), 1e18);

        SafeERC20.safeApprove(dai, address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(staticAToken));
        assertGt(underlyingValue, 1e18 * 9900 / BPS);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped);
        assertEq(staticAToken.balanceOf(address(this)), 0);
        assertEq(staticAToken.balanceOf(address(adapter)), 0);
    }

    function testRoundTrip(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(dai) && 
            amount < type(uint96).max
        );
        
        tip(dai, address(this), amount);

        SafeERC20.safeApprove(dai, address(adapter), amount);
        uint256 wrapped = adapter.wrap(amount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(staticAToken));
        assertGt(underlyingValue, amount * 9900 / BPS);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped);
        assertEq(staticAToken.balanceOf(address(this)), 0);
        assertEq(staticAToken.balanceOf(address(adapter)), 0);
    }
}