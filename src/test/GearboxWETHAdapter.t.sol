// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { DSTestPlus } from "./utils/DSTestPlus.sol";

import { GearboxWETHAdaptor } from "../adapters/gearbox/GearboxWETHAdaptor.sol";

import { IAlchemistV2 } from "../interfaces/IAlchemistV2.sol";
import { IWhitelist } from "../interfaces/IWhitelist.sol";
import { IERC4626 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IAlchemistV2AdminActions } from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
contract GearboxWETHAdaptorTest is DSTestPlus {
	uint256 constant BPS = 10000;
	address constant admin = 0x7e108711771DfdB10743F016D46d75A9379cA043;
  //todo
	address constant whitelistWETHAddress = 0x6996b41c369D3175F18D16ba14952F8C89665710;

	IAlchemistV2 constant alchemist = IAlchemistV2(0x654e16a0b161b150F5d1C8a5ba6E7A7B7760703A);
	IERC20 constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
	IERC4626 constant dWETH = IERC4626(0x04419d3509f13054f60d253E0c79491d9E683399);

	GearboxWETHAdaptor adapter;

	function setUp() external {
		adapter = new GearboxWETHAdaptor(address(dWETH), address(WETH));
		IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
			adapter: address(adapter),
			maximumLoss: 1,
			maximumExpectedValue: 1000000 ether,
			creditUnlockBlocks: 7200
		});
		hevm.startPrank(admin);
		alchemist.addYieldToken(address(dWETH), ytc);
        alchemist.setYieldTokenEnabled(address(dWETH), true);
		alchemist.setTokenAdapter(address(dWETH), address(adapter));
		IWhitelist(whitelistWETHAddress).add(address(this));
		alchemist.setMaximumExpectedValue(address(dWETH), 1000000000e18);
		hevm.stopPrank();
	}

	function testRoundTrip() external {
		deal(address(WETH), address(this), 1e18);

		uint256 startingBalance = dWETH.balanceOf(address(alchemist));

		SafeERC20.safeApprove(address(WETH), address(alchemist), 1e18);
		uint256 shares = alchemist.depositUnderlying(address(dWETH), 1e18, address(this), 0);

		// Test that price function returns value within 0.1% of actual
		uint256 underlyingValue = (shares * adapter.price()) / 10 ** SafeERC20.expectDecimals(address(dWETH));
		assertGt(underlyingValue, (1e18 * 9990) / BPS);

		uint256 unwrapped = alchemist.withdrawUnderlying(address(dWETH), shares, address(this), (shares * 9990) / 10000);

		uint256 endBalance = dWETH.balanceOf(address(alchemist));

		assertEq(WETH.balanceOf(address(this)), unwrapped);
		assertEq(dWETH.balanceOf(address(this)), 0);
		assertEq(dWETH.balanceOf(address(adapter)), 0);
		assertApproxEq(endBalance - startingBalance, 0, 10);
	}

    function testHarvest() external {
        deal(address(dWETH), address(this), 1e18);


        // New position
        SafeERC20.safeApprove(address(dWETH), address(alchemist), 1e18);
        uint256 shares = alchemist.deposit(address(dWETH), 1e18, address(this));
        (int256 debtBefore, ) = alchemist.accounts(address(this));

        // Roll ahead then harvest
        hevm.roll(block.number + 100000);
        hevm.warp(block.timestamp + 165321);
        hevm.prank(admin);
        alchemist.harvest(address(dWETH), 0);

        // Roll ahead one block then check credited amount
        hevm.roll(block.number + 1);
        (int256 debtAfter, ) = alchemist.accounts(address(this));
        assertGt(debtBefore, debtAfter);
    }

    function testLiquidate() external {
        deal(address(dWETH), address(this), 1e18);


        SafeERC20.safeApprove(address(dWETH), address(alchemist), 1e18);
        uint256 shares = alchemist.deposit(address(dWETH), 1e18, address(this));
        uint256 pps = alchemist.getUnderlyingTokensPerShare(address(dWETH));
        uint256 mintAmt = shares * pps / 1e18 / 4;
        alchemist.mint(mintAmt, address(this));

        (int256 debtBefore, ) = alchemist.accounts(address(this));

        uint256 sharesLiquidated = alchemist.liquidate(address(dWETH), shares / 4, mintAmt * 97 / 100);

        (int256 debtAfter, ) = alchemist.accounts(address(this));

        (uint256 sharesLeft, ) =  alchemist.positions(address(this), address(dWETH));

        assertApproxEq(0, uint256(debtAfter), mintAmt - mintAmt * 97 / 100);
        assertEq(shares - sharesLiquidated, sharesLeft);
    }

}

