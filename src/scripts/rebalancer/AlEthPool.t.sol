// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { stdCheats } from "../../../lib/forge-std/src/stdlib.sol";
import { console } from "../../../lib/forge-std/src/console.sol";
import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { DSTestPlus } from "../../test/utils/DSTestPlus.sol";

import { IEthStableMetaPool } from "../../interfaces/external/curve/IEthStableMetaPool.sol";
import { IERC20TokenReceiver } from "../../interfaces/IERC20TokenReceiver.sol";
import { EthAssetManager } from "../../EthAssetManager.sol";

contract AlEthPoolTest is DSTestPlus, stdCheats {
	IEthStableMetaPool constant metaPool = IEthStableMetaPool(0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e);
	EthAssetManager elixir = EthAssetManager(payable(0xe761bf731A06fE8259FeE05897B2687D56933110));
	IERC20 alETH;
	uint256 baseDx;
	uint256 targetDy;
	int128 ethAsset = 0;
	int128 alEthAsset = 1;

	function setUp() public {
		alETH = metaPool.coins(uint256(int256(alEthAsset)));
		baseDx = 100000;

		// SET DESIRED VALUE FOR DY HERE (exchange rate of aleth/eth)
		targetDy = 99999;
	}

	// Test that the change in alETH achieves the desired dy
	function testAlEthRebalance() external {
		// Amount to rebalance alETH
		int256 alEthRebalance = getAlEthChange();

		hevm.startPrank(address(elixir), address(elixir));

		addOrRemoveLiquidity(alEthRebalance, alEthAsset);

		uint256 dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);

		hevm.stopPrank();

		assertApproxEq(targetDy, dy, 10);
	}

	// Test that the change in ETH achieves the desired dy
	function testEthRebalance() external {
		// Amount to rebalance ETH
		int256 ethRebalance = getEthChange();

		hevm.startPrank(address(elixir), address(elixir));

		addOrRemoveLiquidity(ethRebalance, ethAsset);

		uint256 dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);

		hevm.stopPrank();

		assertApproxEq(targetDy, dy, 15);
	}

	// Get the amount of alETH to add or remove from the pool
	function getAlEthChange() public returns (int256) {
		uint256 startBalance;
		uint256 endBalance;
		int256 alEthChange;
		uint256 dy;
		uint256[2] memory balances;
		uint256[2] memory targetBalances;
		uint256 elixirBalance;
		address operator = elixir.operator();

		balances = metaPool.get_balances();
		startBalance = balances[1];

		// make sure elixir can make necessary amount of deposits or withdrawals
		tip(address(metaPool), address(elixir), balances[1]);
		tip(address(alETH), address(elixir), balances[1]);

		hevm.startPrank(address(elixir), address(elixir));

		alETH.approve(address(metaPool), balances[1]);

		dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);
		emit log_named_uint("current dy", dy);

		// logic to add or remove liquidity
		emit log_named_uint("target dy", targetDy);
		loop(targetDy, dy, alEthAsset);

		// get balances after change
		targetBalances = metaPool.get_balances();
		endBalance = targetBalances[1];

		// alEthChange = (int256(endBalance) - int256(startBalance)) * 2;
		alEthChange = (int256(endBalance) - int256(startBalance));
		emit log_named_int("alEth liquidity change in wei", alEthChange);
		emit log_named_int("alEth liquidity change in eth", alEthChange / 1e18);

		// revert pool changes so account can be used to test adding or removing liquidity
		revertPoolChanges(alEthChange, alEthAsset);

		hevm.stopPrank();

		return alEthChange;
	}

	// Get the amount of ETH to add or remove from the pool
	function getEthChange() public returns (int256) {
		uint256 startBalance;
		uint256 endBalance;
		int256 ethChange;
		uint256 dy;
		uint256[2] memory balances;
		uint256[2] memory targetBalances;

		balances = metaPool.get_balances();
		startBalance = balances[0];

		hevm.startPrank(address(elixir), address(elixir));

		// make sure elixir can make necessary amount of deposits or withdrawals
		deal(address(elixir), balances[0] * 2);
		tip(address(metaPool), address(elixir), balances[1]);

		alETH.approve(address(metaPool), balances[1]);

		dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);
		emit log_named_uint("current dy", dy);

		// logic to add or remove liquidity
		emit log_named_uint("target dy", targetDy);
		loop(targetDy, dy, ethAsset);

		// get balances after change
		targetBalances = metaPool.get_balances();
		endBalance = targetBalances[0];

		ethChange = int256(endBalance) - int256(startBalance);
		emit log_named_int("ETH liquidity change in wei", ethChange);
		emit log_named_int("ETH liquidity change in eth", ethChange / 1e18);

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
		uint256 buffer = 0;
		uint256 delta;
		uint256 dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);
		if (dy == target) return true;

		dy > target ? delta = dy - target : delta = target - dy;

		if (delta <= buffer) return true;

		return false;
	}

	// Add or remove liquidity based on given amount
	function addOrRemoveLiquidity(int256 amount, int128 asset) public {
		if (amount > 0) {
			deal(address(elixir), uint256(amount));
			tip(address(alETH), address(elixir), uint256(amount));
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
			deal(address(elixir), uint256(amount));
			tip(address(alETH), address(elixir), uint256(amount));
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
