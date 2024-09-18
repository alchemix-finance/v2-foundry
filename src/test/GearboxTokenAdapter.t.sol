// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "forge-std/Test.sol";
import { DSTestPlus } from "./utils/DSTestPlus.sol";

// Correct the import path or contract name as necessary
import { GearboxTokenAdapter } from "../adapters/gearbox/GearboxTokenAdapter.sol";

import { IAlchemistV2 } from "../../src/interfaces/IAlchemistV2.sol";
import { IWhitelist } from "../interfaces/IWhitelist.sol";
import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IAlchemistV2AdminActions } from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
contract GearboxTokenAdaptorTest is DSTestPlus {
	uint256 constant BPS = 10000;
	address constant admin = 0x886FF7a2d46dcc2276e2fD631957969441130847;
	address constant whitelistWETHAddress = 0x6996b41c369D3175F18D16ba14952F8C89665710;
	address constant farmingToken = 0xf3b7994e4dA53E04155057Fd61dc501599d57877;

	IERC4626 constant dWETH = IERC4626(0x04419d3509f13054f60d253E0c79491d9E683399);

	IAlchemistV2 constant alchemist = IAlchemistV2(0x654e16a0b161b150F5d1C8a5ba6E7A7B7760703A);
	IERC20 constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
	GearboxTokenAdapter adapter;

	function setUp() external {
		adapter = new GearboxTokenAdapter(address(farmingToken), address(dWETH), address(WETH), 0x6D2caB5Bd20ce2e9F3e1d77B66f0c90aEDc674B6);
		IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
			adapter: address(adapter),
			maximumLoss: 1,
			maximumExpectedValue: 1000000 ether,
			creditUnlockBlocks: 7200
		});
		hevm.startPrank(admin);
		alchemist.addYieldToken(address(0xf3b7994e4dA53E04155057Fd61dc501599d57877), ytc);
		alchemist.setYieldTokenEnabled(address(farmingToken), true);
		alchemist.setTokenAdapter(address(farmingToken), address(adapter));
		IWhitelist(whitelistWETHAddress).add(address(this));
		alchemist.setMaximumExpectedValue(address(farmingToken), 1000000000e18);
		hevm.stopPrank();
	}

	function testRoundTrip() external {
		deal(address(WETH), address(this), 1e18);

		uint256 startingBalance = IERC20(farmingToken).balanceOf(address(alchemist));

		SafeERC20.safeApprove(address(WETH), address(alchemist), 1e18);
		uint256 shares = alchemist.depositUnderlying(address(farmingToken), 1e18, address(this), 0);

		// Test that price function returns value within 0.1% of actual
		uint256 underlyingValue = (shares * adapter.price()) / 10 ** SafeERC20.expectDecimals(address(farmingToken));
		assertGt(underlyingValue, (1e18 * 9990) / BPS);

		uint256 unwrapped = alchemist.withdrawUnderlying(
			address(farmingToken),
			shares,
			address(this),
			(shares * 9990) / 10000
		);

		uint256 endBalance = IERC20(farmingToken).balanceOf(address(alchemist));

		assertEq(WETH.balanceOf(address(this)), unwrapped);
		assertEq(IERC20(farmingToken).balanceOf(address(this)), 0);
		assertEq(IERC20(farmingToken).balanceOf(address(adapter)), 0);
		assertEq(IERC20(farmingToken).balanceOf(address(alchemist)), 0);
		assertApproxEq(endBalance - startingBalance, 0, 10);
	}

	function testHarvest() external {
		deal(address(farmingToken), address(this), 1e18);

		// New position
		SafeERC20.safeApprove(address(farmingToken), address(alchemist), 1e18);
		uint256 shares = alchemist.deposit(address(farmingToken), 1e18, address(this));
		(int256 debtBefore, ) = alchemist.accounts(address(this));
		uint256 priceBefore = adapter.price();

		// Roll ahead then harvest
		hevm.roll(block.number + 1000);
		hevm.warp(block.timestamp + 16532);
		hevm.prank(admin);
		alchemist.harvest(address(farmingToken), 0);
		// Roll ahead one block then check credited amount
		uint256 priceAfter = adapter.price();

		hevm.roll(block.number + 10000);
		(int256 debtAfter, ) = alchemist.accounts(address(this));

		assertGt(debtBefore, debtAfter);
	}

	function testLiquidate() external {
		deal(address(farmingToken), address(this), 1e18);

		SafeERC20.safeApprove(address(farmingToken), address(alchemist), 1e18);
		uint256 shares = alchemist.deposit(address(farmingToken), 1e18, address(this));
		uint256 pps = alchemist.getUnderlyingTokensPerShare(address(farmingToken));
		uint256 mintAmt = (shares * pps) / 1e18 / 4;
		alchemist.mint(mintAmt, address(this));

		(int256 debtBefore, ) = alchemist.accounts(address(this));

		uint256 sharesLiquidated = alchemist.liquidate(address(farmingToken), shares / 4, (mintAmt * 97) / 100);

		(int256 debtAfter, ) = alchemist.accounts(address(this));

		(uint256 sharesLeft, ) = alchemist.positions(address(this), address(farmingToken));

		assertApproxEq(0, uint256(debtAfter), mintAmt - (mintAmt * 97) / 100);
		assertEq(shares - sharesLiquidated, sharesLeft);
	}
}
