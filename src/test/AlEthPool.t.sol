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
		targetDy = 99900;
		poolChange = getPoolChange();
	}

	// Test to confirm the change in alETH achieves the desired dy
	function testPoolChange() external {
		hevm.startPrank(gauge, gauge);

		addOrRemoveLiquidity(poolChange, gauge);

		uint256 dy = metaPool.get_dy(1, 0, baseDx);

		hevm.stopPrank();

		assertApproxEq(targetDy, dy, 10);
	}

	function getPoolChange() public returns (int256) {
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

		hevm.stopPrank();

		dy = metaPool.get_dy(1, 0, baseDx);
		emit log_named_uint("current dy", dy);

		// logic to add or remove liquidity
		emit log_named_uint("target dy", targetDy);
		loop(targetDy, dy, gauge);

		// get balances after change
		targetBalances = metaPool.get_balances();
		endBalance = targetBalances[1];

		alEthChange = int256(endBalance) - int256(startBalance);
		emit log_named_int("alEth liquidity change", alEthChange);

		// revert pool changes so account can be used to test adding or removing liquidity
		revertPoolChanges(alEthChange, gauge);

		return alEthChange;
	}

	function loop(
		uint256 target,
		uint256 dy,
		address account
	) public {
		// Amount to increase or decrease alETH liquidity by
		uint256 change = 1e18;
		bool solved = false;

		while (!solved) {
			balancePool(change, dy, target, account);
			solved = dxSolved(target);
		}
	}

	function balancePool(
		uint256 change,
		uint256 dy,
		uint256 target,
		address account
	) public {
		hevm.startPrank(account, account);
		if (dy > target) {
			metaPool.add_liquidity([uint256(0), change], 0);
		} else {
			metaPool.remove_liquidity_one_coin(change, 1, 0);
		}
		hevm.stopPrank();
	}

	function dxSolved(uint256 target) public returns (bool) {
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

	function addOrRemoveLiquidity(int256 change, address account) public {
		if (change > 0) {
			tip(address(alETH), gauge, uint256(change));
			alETH.approve(address(metaPool), uint256(change));
			metaPool.add_liquidity([uint256(0), uint256(change)], 0);
		} else {
			metaPool.remove_liquidity_one_coin(uint256(change * -1), 1, 0);
		}
	}

	function revertPoolChanges(int256 change, address account) public {
		hevm.startPrank(account, account);
		if (change < 0) {
			tip(address(alETH), gauge, uint256(change));
			alETH.approve(address(metaPool), uint256(change));
			metaPool.add_liquidity([uint256(0), uint256(change * -1)], 0);
		} else {
			metaPool.remove_liquidity_one_coin(uint256(change), 1, 0);
		}
		hevm.stopPrank();
	}
}
