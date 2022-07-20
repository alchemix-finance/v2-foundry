// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { stdCheats } from "../../lib/forge-std/src/stdlib.sol";
import { console } from "../../lib/forge-std/src/console.sol";
import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";

import { IEthStableMetaPool } from "../interfaces/external/curve/IEthStableMetaPool.sol";
import { ICalculator } from "../interfaces/external/curve/ICalculator.sol";
import { EthAssetManager } from "../EthAssetManager.sol";
import { IERC20TokenReceiver } from "../interfaces/IERC20TokenReceiver.sol";

contract AlEthPoolTest is DSTestPlus, stdCheats {
	IEthStableMetaPool constant metaPool = IEthStableMetaPool(0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e);
	IERC20TokenReceiver constant manager = IERC20TokenReceiver(0xe761bf731A06fE8259FeE05897B2687D56933110);
	ICalculator constant calculator = ICalculator(0xc1DB00a8E5Ef7bfa476395cdbcc98235477cDE4E);
	address gauge = 0x12dCD9E8D1577b5E4F066d8e7D404404Ef045342;
	IERC20 alETH;
	uint256 baseDx;
	uint256 targetDy;
	int256 poolChange;

	function setUp() public {
		alETH = metaPool.coins(1);
		baseDx = 100000;

		// set desired dy here
		targetDy = 99999;

		// Amount to change the pool by
		poolChange = getAlEthChange();
	}

	// Test the change in alETH achieves the desired dy
	function testPoolChange() external {
		hevm.startPrank(gauge, gauge);

		addOrRemoveLiquidity(poolChange);

		uint256 dy = metaPool.get_dy(1, 0, baseDx);

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

		dy = metaPool.get_dy(1, 0, baseDx);
		emit log_named_uint("current dy", dy);

		// logic to add or remove liquidity
		emit log_named_uint("target dy", targetDy);
		loop(targetDy, dy);

		// get balances after change
		targetBalances = metaPool.get_balances();
		endBalance = targetBalances[1];

		alEthChange = int256(endBalance) - int256(startBalance);
		emit log_named_int("alEth liquidity change", alEthChange);

		// revert pool changes so account can be used to test adding or removing liquidity
		revertPoolChanges(alEthChange);

		hevm.stopPrank();

		return alEthChange;
	}

	// Until target dy is reached add or remove liquidity
	function loop(uint256 target, uint256 dy) public {
		// Amount to increase or decrease alETH liquidity by
		uint256 amount = 1e18;
		bool solved = false;

		while (!solved) {
			balancePool(amount, dy, target);
			solved = dxSolved(target);
		}
	}

	// Determine to add or remove alETH by an amount
	function balancePool(
		uint256 amount,
		uint256 dy,
		uint256 target
	) public {
		if (dy > target) {
			metaPool.add_liquidity([uint256(0), amount], 0);
		} else {
			metaPool.remove_liquidity_one_coin(amount, 1, 0);
		}
	}

	// Check if target dy has been reached
	function dxSolved(uint256 target) public view returns (bool) {
		uint256 buffer = 3;
		uint256 dy = metaPool.get_dy(1, 0, baseDx);
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
	function addOrRemoveLiquidity(int256 amount) public {
		if (amount > 0) {
			tip(address(alETH), gauge, uint256(amount));
			alETH.approve(address(metaPool), uint256(amount));
			metaPool.add_liquidity([uint256(0), uint256(amount)], 0);
		} else {
			metaPool.remove_liquidity_one_coin(uint256(amount * -1), 1, 0);
		}
	}

	// Revert adding or removing liquidity
	function revertPoolChanges(int256 amount) public {
		if (amount < 0) {
			tip(address(alETH), gauge, uint256(amount));
			alETH.approve(address(metaPool), uint256(amount));
			metaPool.add_liquidity([uint256(0), uint256(amount * -1)], 0);
		} else {
			metaPool.remove_liquidity_one_coin(uint256(amount), 1, 0);
		}
	}
}
