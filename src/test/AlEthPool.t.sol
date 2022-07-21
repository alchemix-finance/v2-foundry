// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { stdCheats } from "../../lib/forge-std/src/stdlib.sol";
import { console } from "../../lib/forge-std/src/console.sol";
import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";

import { IEthStableMetaPool } from "../interfaces/external/curve/IEthStableMetaPool.sol";
import { IERC20TokenReceiver } from "../interfaces/IERC20TokenReceiver.sol";

contract AlEthPoolTest is DSTestPlus, stdCheats {
	IEthStableMetaPool constant metaPool = IEthStableMetaPool(0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e);
	IERC20TokenReceiver constant manager = IERC20TokenReceiver(0xe761bf731A06fE8259FeE05897B2687D56933110);
	address gauge = 0x12dCD9E8D1577b5E4F066d8e7D404404Ef045342;
	// address ethDepositor = 0xF63F5FCC54f5fd11f3c098053F330E032E4D9259;
	IERC20 alETH;
	uint256 baseDx;
	uint256 targetDy;
	int256 alEthRebalance;
	int256 ethRebalance;
	int128 ethAsset = 0;
	int128 alEthAsset = 1;

	function setUp() public {
		alETH = metaPool.coins(uint256(int256(alEthAsset)));
		baseDx = 100000;

		// set desired dy here
		targetDy = 99000;
	}

	// Test that the change in alETH achieves the desired dy
	function testAlEthRebalance() external {
		// Amount to rebalance alETH
		alEthRebalance = getAlEthChange();

		hevm.startPrank(gauge, gauge);

		addOrRemoveLiquidity(alEthRebalance, alEthAsset);

		uint256 dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);

		hevm.stopPrank();

		assertApproxEq(targetDy, dy, 10);
	}

	// Test that the change in ETH achieves the desired dy
	function testEthRebalance() external {
		// Amount to rebalance ETH
		ethRebalance = getEthChange();

		hevm.startPrank(gauge, gauge);

		addOrRemoveLiquidity(ethRebalance, ethAsset);

		uint256 dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);

		hevm.stopPrank();

		assertApproxEq(targetDy, dy, 10);
	}

	// Get the amount of alETH to add or remove from the pool
	function getAlEthChange() public returns (int256) {
		uint256 startBalance;
		uint256 endBalance;
		uint256 alEthBalance;
		int256 alEthChange;
		uint256 dy;
		uint256[2] memory balances;
		uint256[2] memory targetBalances;

		balances = metaPool.get_balances();
		startBalance = balances[1];

		hevm.startPrank(gauge, gauge);

		// make sure gauge has enough alEth to deposit
		tip(address(alETH), gauge, balances[1]);

		alEthBalance = alETH.balanceOf(gauge);
		alETH.approve(address(metaPool), alEthBalance);

		dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);
		emit log_named_uint("current dy", dy);

		// logic to add or remove liquidity
		emit log_named_uint("target dy", targetDy);
		loop(targetDy, dy, alEthAsset);

		// get balances after change
		targetBalances = metaPool.get_balances();
		endBalance = targetBalances[1];

		alEthChange = int256(endBalance) - int256(startBalance);
		emit log_named_int("alEth liquidity change", alEthChange);

		// revert pool changes so account can be used to test adding or removing liquidity
		revertPoolChanges(alEthChange, alEthAsset);

		hevm.stopPrank();

		return alEthChange;
	}

	// Get the amount of ETH to add or remove from the pool
	function getEthChange() public returns (int256) {
		uint256 startBalance;
		uint256 endBalance;
		uint256 ethBalance;
		int256 ethChange;
		uint256 dy;
		uint256[2] memory balances;
		uint256[2] memory targetBalances;

		balances = metaPool.get_balances();
		startBalance = balances[0];

		hevm.startPrank(address(0xbeef), address(0xbeef));

		// Ensure account has enough alETH and ETH to test
		deal(address(0xbeef), balances[0] * 2);
		tip(address(alETH), address(0xbeef), balances[1]);
		alETH.approve(address(metaPool), balances[1]);

		// add tokens to the pool to maintain dy and allow account to withdraw for testing
		metaPool.add_liquidity{ value: startBalance }([startBalance, balances[1]], 0);

		dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);
		emit log_named_uint("current dy", dy);

		// logic to add or remove liquidity
		emit log_named_uint("target dy", targetDy);
		loop(targetDy, dy, ethAsset);

		// get balances after change
		targetBalances = metaPool.get_balances();
		endBalance = targetBalances[0];

		ethChange = int256(endBalance) - int256(startBalance);
		emit log_named_int("ETH liquidity change", ethChange);

		// revert pool changes so account can be used to test adding or removing liquidity
		revertPoolChanges(ethChange, ethAsset);

		hevm.stopPrank();

		return ethChange;
	}

	// Until target dy is reached add or remove liquidity
	function loop(
		uint256 target,
		uint256 dy,
		int128 asset
	) public {
		// Amount to increase or decrease liquidity by
		uint256 amount = 0.1e18;
		bool solved = false;

		while (!solved) {
			balancePool(amount, dy, target, asset);
			solved = dxSolved(target);
		}
	}

	// Determine to add or remove alETH by an amount
	function balancePool(
		uint256 amount,
		uint256 dy,
		uint256 target,
		int128 asset
	) public {
		if (dy > target) {
			// determine whether to add alETH or remove ETH
			asset == 1
				? metaPool.add_liquidity([uint256(0), amount], 0)
				: metaPool.remove_liquidity_one_coin(amount, asset, 0);
		} else {
			asset == 1
				? metaPool.remove_liquidity_one_coin(amount, asset, 0)
				: metaPool.add_liquidity{ value: amount }([amount, uint256(0)], 0);
		}
	}

	// Check if target dy has been reached
	function dxSolved(uint256 target) public view returns (bool) {
		uint256 buffer = 3;
		uint256 dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);
		if (dy == target) {
			return true;
		}

		// account for result being slightly more
		if (target > dy && target - buffer < dy) {
			return true;
		}

		// account for result being slightly less
		if (target < dy && target + buffer > dy) {
			return true;
		}

		return false;
	}

	// Add or remove liquidity based on given amount
	function addOrRemoveLiquidity(int256 amount, int128 asset) public {
		if (amount > 0) {
			deal(gauge, uint256(amount));
			tip(address(alETH), gauge, uint256(amount));
			alETH.approve(address(metaPool), uint256(amount));
			// determine whether to add ETH or alETH
			asset == 1
				? metaPool.add_liquidity([uint256(0), uint256(amount)], 0)
				: metaPool.add_liquidity{ value: uint256(amount) }([uint256(amount), uint256(0)], 0);
		} else {
			metaPool.remove_liquidity_one_coin(uint256(amount * -1), asset, 0);
		}
	}

	// Revert adding or removing liquidity
	function revertPoolChanges(int256 amount, int128 asset) public {
		if (amount < 0) {
			deal(gauge, uint256(amount));
			tip(address(alETH), gauge, uint256(amount));
			alETH.approve(address(metaPool), uint256(amount));
			// determine whether to add ETH or alETH
			asset == 1
				? metaPool.add_liquidity([uint256(0), uint256(amount * -1)], 0)
				: metaPool.add_liquidity{ value: uint256(amount * -1) }([uint256(amount * -1), uint256(0)], 0);
		} else {
			metaPool.remove_liquidity_one_coin(uint256(amount), asset, 0);
		}
	}
}
