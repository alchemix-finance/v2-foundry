// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { DSTestPlus } from "./utils/DSTestPlus.sol";

import { DSRAdapter } from "../adapters/maker/DSRAdapter.sol";

import { IAlchemistV2 } from "../interfaces/IAlchemistV2.sol";
import { IWhitelist } from "../interfaces/IWhitelist.sol";
import { IERC4626 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IAlchemistV2AdminActions } from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
contract WstETHAdapterV1Test is DSTestPlus {
	uint256 constant BPS = 10000;
	address constant admin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
	address constant whitelistUSDAddress = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;

	IAlchemistV2 constant alchemist = IAlchemistV2(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd);
	IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
	IERC4626 constant sDAI = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);

	DSRAdapter adapter;

	function setUp() external {
		adapter = new DSRAdapter(address(sDAI), address(DAI));
		IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
			adapter: address(adapter),
			maximumLoss: 1,
			maximumExpectedValue: 1000000 ether,
			creditUnlockBlocks: 7200
		});
		hevm.startPrank(admin);
		alchemist.addYieldToken(address(sDAI), ytc);
        alchemist.setYieldTokenEnabled(address(sDAI), true);
		alchemist.setTokenAdapter(address(sDAI), address(adapter));
		IWhitelist(whitelistUSDAddress).add(address(this));
		alchemist.setMaximumExpectedValue(address(sDAI), 1000000000e18);
		hevm.stopPrank();
	}

	function testRoundTrip() external {
		deal(address(DAI), address(this), 1e18);

		uint256 startingBalance = sDAI.balanceOf(address(alchemist));

		SafeERC20.safeApprove(address(DAI), address(alchemist), 1e18);
		uint256 shares = alchemist.depositUnderlying(address(sDAI), 1e18, address(this), 0);

		// Test that price function returns value within 0.1% of actual
		uint256 underlyingValue = (shares * adapter.price()) / 10 ** SafeERC20.expectDecimals(address(sDAI));
		assertGt(underlyingValue, (1e18 * 9990) / BPS);

		uint256 unwrapped = alchemist.withdrawUnderlying(address(sDAI), shares, address(this), (shares * 9990) / 10000);

		uint256 endBalance = sDAI.balanceOf(address(alchemist));

		assertEq(DAI.balanceOf(address(this)), unwrapped);
		assertEq(sDAI.balanceOf(address(this)), 0);
		assertEq(sDAI.balanceOf(address(adapter)), 0);
		assertApproxEq(endBalance - startingBalance, 0, 10);
	}
}
