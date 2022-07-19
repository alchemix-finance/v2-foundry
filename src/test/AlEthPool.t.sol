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
	uint256 dx;
	int256 alEthChange;
	uint256 targetDy;

	function setUp() public {
		alETH = metaPool.coins(1);
		dx = 1000000000000000000;
		targetDy = 970000000000000000;
	}

	function testPool() external {
		uint256 startBalance;
		uint256 endBalance;
		uint256 alEthBalance;
		uint256 dy;
		uint256[2] memory balances;
		uint256[2] memory targetBalances;

		hevm.startPrank(gauge, gauge);

		balances = metaPool.get_balances();
		startBalance = balances[1];

		// make sure gauge has enough alEth to deposit
		tip(address(alETH), gauge, balances[1]);

		alEthBalance = alETH.balanceOf(gauge);
		alETH.approve(address(metaPool), alEthBalance);

		dy = metaPool.get_dy(1, 0, 1e18);
		emit log_named_uint("dy", dy);

		// logic to add or remove liquidity
		targetDy = dy - 1e9;
		emit log_named_uint("targetDy", targetDy);
		loop(targetDy, dy);

		// get balances after change
		targetBalances = metaPool.get_balances();
		endBalance = targetBalances[1];

		alEthChange = int256(endBalance) - int256(startBalance);
		emit log_named_int("alEth liquidity change", alEthChange);

		hevm.stopPrank();
	}

	// Test to confirm the change in alETH achieves the desired dy
	function testPoolChange() external {
		hevm.startPrank(address(0xbeef), address(0xbeef));

		if (alEthChange > 0) {
			tip(address(alETH), address(0xbeef), uint256(alEthChange));
			alETH.approve(address(metaPool), uint256(alEthChange));
			metaPool.add_liquidity([uint256(0), uint256(alEthChange)], 0);
		} else {
			metaPool.remove_liquidity_one_coin(uint256(alEthChange * -1), 1, 0);
		}

		uint256 currentDy = metaPool.get_dy(1, 0, dx);
		targetDy = currentDy - 1e9;

		assertApproxEq(targetDy, currentDy, 1e6);
	}

	function loop(uint256 target, uint256 dy) public {
		// Amount to increase or decrease alETH liquidity by
		uint256 change = 1e15;
		bool solved = false;

		while (!solved) {
			balancePool(change, dy, target);
			solved = dxSolved(target);
		}
	}

	function balancePool(
		uint256 change,
		uint256 dy,
		uint256 target
	) public {
		if (dy > target) {
			metaPool.add_liquidity([uint256(0), change], 0);
		} else {
			metaPool.remove_liquidity_one_coin(change, 1, 0);
		}
	}

	function dxSolved(uint256 target) public returns (bool) {
		uint256 buffer = 1e9;
		uint256 dy = metaPool.get_dy(1, 0, dx);
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

	function testGetDx() external {
		uint256 dx;

		int128 n_coins = int128(int256(metaPool.totalSupply()));
		uint256[2] memory poolBalances = metaPool.get_balances();
		uint256[8] memory balances = [poolBalances[0], poolBalances[1], 0, 0, 0, 0, 0, 0];
		uint256 amp = metaPool.A();
		uint256 fee = metaPool.fee();
		uint256[8] memory rates = [
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0)
		];
		uint256[8] memory precisions = [
			uint256(1000000000000000000),
			uint256(1000000000000000000),
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0)
		];
		bool underlying = true;
		int128 i = 1;
		int128 j = 0;
		uint256 dy = 1000000000000000000;

		dx = calculator.get_dx(int128(n_coins), balances, amp, fee, rates, precisions, underlying, i, j, dy);

		emit log_named_uint("dx", dx);
	}
}

// cast call 0xc1DB00a8E5Ef7bfa476395cdbcc98235477cDE4E "get_dx(int128,uint256[8],uint256,uint256,uint256[8],uint256[8],bool,int128,int128,uint256)(uint256)" 38237110009691290102777 "[8642515749474252628415,29731013613678119677889,0,0,0,0,0,0]" 100 4000000 "[0,0,0,0,0,0,0,0]" "[1000000000000000000,1000000000000000000,0,0,0,0,0,0]" true 1 0 1000000000000000000
