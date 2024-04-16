// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { DSTestPlus } from "../../test/utils/DSTestPlus.sol";

import { IEthStableMetaPool } from "../../interfaces/external/curve/IEthStableMetaPool.sol";
import { IERC20TokenReceiver } from "../../interfaces/IERC20TokenReceiver.sol";
import { IConvexRewards } from "../../interfaces/external/convex/IConvexRewards.sol";
import { EthAssetManager } from "../../EthAssetManager.sol";

contract AlEthPoolTest is DSTestPlus {
	IEthStableMetaPool constant metaPool = IEthStableMetaPool(0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e);
	EthAssetManager elixir = EthAssetManager(payable(0xe761bf731A06fE8259FeE05897B2687D56933110));
	IConvexRewards convex = IConvexRewards(0x48Bc302d8295FeA1f8c3e7F57D4dDC9981FEE410);
	IERC20 alETH = IERC20(0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6);
	IERC20 wETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
	int128 ethAsset = 0;
	int128 alEthAsset = 1;
	uint256 baseDx = 100000;
	uint256 minAmount = 0;
	uint256 targetDy;
	uint256 totalSupply;
	uint256 poolAlEthRatio;
	uint256 poolEthRatio;
	uint256[2] metaPoolBalances;
	uint256 elixirPoolTokenBalance;
	uint256 elixirAlEthAccountBalance;
	uint256 elixirEthAccountBalance;
	uint256 elixirWethAccountBalance;
	uint256 elixirEthPoolBalance;
	uint256 elixirAlEthPoolBalance;

	function setUp() public {
		// SET DESIRED VALUE FOR DY HERE (exchange rate of aleth/eth)
		targetDy = 99111;

		totalSupply = metaPool.totalSupply();
		metaPoolBalances = metaPool.get_balances();
		poolAlEthRatio = (metaPoolBalances[1] * 10000) / totalSupply;
		poolEthRatio = (metaPoolBalances[0] * 10000) / totalSupply;

		uint256 convexBalance = convex.balanceOf(address(elixir));
		address operator = elixir.operator();

		// Withdraw pool tokens from convex
		hevm.startPrank(operator, operator);
		elixir.withdrawMetaPoolTokens(convexBalance);
		hevm.stopPrank();

		elixirAlEthAccountBalance = alETH.balanceOf(address(elixir));
		elixirWethAccountBalance = wETH.balanceOf(address(elixir));
		elixirEthAccountBalance = elixirWethAccountBalance;
		elixirPoolTokenBalance = metaPool.balanceOf(address(elixir));
		elixirAlEthPoolBalance = (elixirPoolTokenBalance * poolAlEthRatio) / 10000;
		elixirEthPoolBalance = (elixirPoolTokenBalance * poolEthRatio) / 10000;

		// Make sure elixir can make necessary amount of deposits or withdrawals
		// to get a final liquidity calculation
		deal(address(metaPool), address(elixir), elixirPoolTokenBalance);
		deal(address(alETH), address(elixir), metaPoolBalances[1]);
		hevm.deal(address(elixir), elixirWethAccountBalance);
		hevm.deal(address(elixir), metaPoolBalances[0]);
	}

	// Test that the change in alETH achieves the desired dy
	function testAlEthRebalance() external {
		// Amount to rebalance alETH
		int256 alEthRebalance = getAlEthChange();

		hevm.startPrank(address(elixir), address(elixir));

		addOrRemoveLiquidity(alEthRebalance, alEthAsset);

		uint256 dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);

		emit log_named_uint("updated dy", dy);

		hevm.stopPrank();

		assertApproxEq(targetDy, dy, 15);
	}

	// Test that the change in ETH achieves the desired dy
	function testEthRebalance() external {
		// Amount to rebalance ETH
		int256 ethRebalance = getEthChange();

		hevm.startPrank(address(elixir), address(elixir));

		addOrRemoveLiquidity(ethRebalance, ethAsset);

		uint256 dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);

		emit log_named_uint("updated dy", dy);

		hevm.stopPrank();

		assertApproxEq(targetDy, dy, 15);
	}

	// Get the amount of alETH to add or remove from the pool
	function getAlEthChange() public returns (int256) {
		uint256 dy;
		uint256 startBalance = metaPoolBalances[1];
		uint256 endBalance;
		int256 alEthChange;
		int256 elixirDelta;
		uint256[2] memory targetBalances;

		hevm.startPrank(address(elixir), address(elixir));

		alETH.approve(address(metaPool), startBalance);

		dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);
		emit log_named_uint("current dy", dy);
		emit log_named_uint("target dy", targetDy);

		// Logic to add or remove liquidity
		loop(targetDy, dy, alEthAsset);

		// Get balances after liquidity change
		targetBalances = metaPool.get_balances();
		endBalance = targetBalances[1];

		alEthChange = (int256(endBalance) - int256(startBalance));

		// If alEthChange is greater than 0 alETH needs to be added to the pool
		if (alEthChange > 0) {
			elixirDelta = int256(elixirAlEthAccountBalance) - alEthChange;
			// If the delta is less than 0 the elixir does not
			// have enough alETH to deposit into the pool
			if (elixirDelta < 0) {
				emit log("INSUFFICIENT ELIXIR ALETH ACCOUNT BALANCE");
				emit log_named_int("alETH account balance needed to reach target", alEthChange);
				emit log_named_uint("Elixir alETH account balance", elixirAlEthAccountBalance);
				emit log_named_uint("Amount short", uint256(elixirDelta * -1));

				revertPoolChanges(alEthChange, alEthAsset);
				hevm.stopPrank();

				// Return the max amount of alETH the elixir could add to the pool
				return int256(elixirAlEthAccountBalance);
			}
		}
		// If alEthChange is less than 0 alETH needs to be removed from the pool
		else {
			elixirDelta = int256(elixirAlEthPoolBalance) + alEthChange;
			// If the delta is less than 0 the elixir does not
			// have enough alETH in the pool to withdraw
			if (elixirDelta < 0) {
				emit log("INSUFFICIENT ELIXIR ALETH POOL BALANCE");
				emit log_named_int("alETH pool balance needed to reach target", (alEthChange * -1));
				emit log_named_uint("Elixir alETH pool balance", elixirAlEthPoolBalance);
				emit log_named_uint("Amount short", uint256(elixirDelta * -1));

				revertPoolChanges(alEthChange, alEthAsset);
				hevm.stopPrank();

				// Return the max amount of alETH the elixir can remove from the pool
				return int256(int256(elixirAlEthPoolBalance) * -1);
			}
		}

		emit log_named_int("alETH liquidity change in wei", alEthChange);
		emit log_named_int("alETH liquidity change in eth", alEthChange / 1e18);

		// Revert pool changes made to test adding or removing liquidity based on calculations
		revertPoolChanges(alEthChange, alEthAsset);
		hevm.stopPrank();

		// Return amount of alETH required to achieve the target exchange rate
		return alEthChange;
	}

	// Get the amount of ETH to add or remove from the pool
	function getEthChange() public returns (int256) {
		uint256 dy;
		uint256 startBalance = metaPoolBalances[0];
		uint256 endBalance;
		int256 ethChange;
		int256 elixirDelta;
		uint256[2] memory targetBalances;

		hevm.startPrank(address(elixir), address(elixir));

		dy = metaPool.get_dy(alEthAsset, ethAsset, baseDx);
		emit log_named_uint("current dy", dy);
		emit log_named_uint("target dy", targetDy);

		// Logic to add or remove liquidity
		loop(targetDy, dy, ethAsset);

		// Get balances after change
		targetBalances = metaPool.get_balances();
		endBalance = targetBalances[0];

		ethChange = int256(endBalance) - int256(startBalance);

		// If ethChange is greater than 0 ETH needs to be added to the pool
		if (ethChange > 0) {
			elixirDelta = int256(elixirEthAccountBalance) - ethChange;
			// If the delta is less than 0 the elixir does not
			// have enough ETH to deposit into the pool
			if (elixirDelta < 0) {
				emit log("INSUFFICIENT ELIXIR ETH ACCOUNT BALANCE");
				emit log_named_int("ETH account balance needed to reach target", ethChange);
				emit log_named_uint("Elixir ETH account balance", elixirEthAccountBalance);
				emit log_named_uint("Amount short", uint256(elixirDelta * -1));

				revertPoolChanges(ethChange, ethAsset);
				hevm.stopPrank();

				// Return the max amount of ETH the elixir could add to the pool
				return int256(elixirEthAccountBalance);
			}
		}
		// If ethChange is less than 0 ETH needs to be removed from the pool
		else {
			elixirDelta = int256(elixirEthPoolBalance) + ethChange;
			// If the delta is less than 0 the elixir does not
			// have enough ETH in the pool to withdraw
			if (elixirDelta < 0) {
				emit log("INSUFFICIENT ELIXIR ETH POOL BALANCE");
				emit log_named_int("ETH pool balance needed to reach target", (ethChange * -1));
				emit log_named_uint("Elixir ETH pool balance", elixirEthPoolBalance);
				emit log_named_uint("Amount short", uint256(elixirDelta * -1));

				revertPoolChanges(ethChange, ethAsset);
				hevm.stopPrank();

				// Return the max amount of ETH the elixir can remove from the pool
				return int256(int256(elixirEthPoolBalance) * -1);
			}
		}

		emit log_named_int("ETH liquidity change in wei", ethChange);
		emit log_named_int("ETH liquidity change in eth", ethChange / 1e18);

		// Revert pool changes so account can be used to test adding or removing liquidity
		revertPoolChanges(ethChange, ethAsset);
		hevm.stopPrank();

		// Return amount of ETH required to achieve the target exchange rate
		return ethChange;
	}

	// Until target dy is reached add or remove liquidity
	function loop(
		uint256 target,
		uint256 dy,
		int128 token
	) public {
		// Amount to increase or decrease liquidity by
		uint256 amount = 0.1e18;
		bool solved = false;

		while (!solved) {
			balancePool(amount, dy, target, token);
			solved = dxSolved(target);
		}
	}

	// Add or remove liquidity by amount
	function balancePool(
		uint256 amount,
		uint256 dy,
		uint256 target,
		int128 token
	) public {
		if (dy > target) {
			// Determine whether to add alETH or remove ETH
			token == 1
				? metaPool.add_liquidity([uint256(0), amount], minAmount)
				: metaPool.remove_liquidity_one_coin(amount, token, minAmount);
		} else {
			token == 1
				? metaPool.remove_liquidity_one_coin(amount, token, minAmount)
				: metaPool.add_liquidity{ value: amount }([amount, uint256(0)], minAmount);
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

	// Add or remove liquidity based on given amount and token
	function addOrRemoveLiquidity(int256 amount, int128 token) public {
		if (amount > 0) {
			// Determine whether to add ETH or alETH
			token == 1
				? metaPool.add_liquidity([uint256(0), uint256(amount)], minAmount)
				: metaPool.add_liquidity{ value: uint256(amount) }([uint256(amount), uint256(0)], minAmount);
		} else {
			metaPool.remove_liquidity_one_coin(uint256(amount * -1), token, minAmount);
		}
	}

	// Revert liquidity changes
	function revertPoolChanges(int256 amount, int128 token) public {
		if (amount > 0) {
			metaPool.remove_liquidity_one_coin(uint256(amount), token, minAmount);
		} else {
			// Determine whether to add ETH or alETH
			token == 1
				? metaPool.add_liquidity([uint256(0), uint256(amount * -1)], minAmount)
				: metaPool.add_liquidity{ value: uint256(amount * -1) }([uint256(amount * -1), uint256(0)], minAmount);
		}
	}
}
