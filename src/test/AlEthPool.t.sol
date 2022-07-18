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
	IERC20 alETH;

	function setUp() public {
		alETH = metaPool.coins(1);
	}

	function testPool() external {
		uint256 balance;
		uint256 dy;

		hevm.prank(address(manager));
		// tip(address(alETH), address(0xdead), 1e18);

		balance = alETH.balanceOf(address(manager));
		console.log("~ balance", balance / 1e18);

		dy = metaPool.get_dy(1, 0, 1e18);
		emit log_named_uint("dy", dy);

		alETH.approve(address(manager), balance);
		metaPool.add_liquidity([uint256(0), uint256(1e18)], 0);

		dy = metaPool.get_dy(1, 0, 1e18);
		emit log_named_uint("dy2", dy);

		assertEq(balance, dy);
	}

	function testGetDx() external {
		uint256 dx;
		uint256 balance = 10;
		uint256[8] memory balances = [
			uint256(8642515749474252628415),
			uint256(29731013613678119677889),
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0),
			uint256(0)
		];
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

		dx = calculator.get_dx(
			int128(38237110009691290102777),
			balances,
			100,
			4000000,
			rates,
			precisions,
			bool(true),
			int128(1),
			int128(0),
			1000000000000000000
		);
		emit log_named_uint("dx", dx);
		console.log("~ dx", dx);

		assertEq(balance, dx);
	}
}

// cast call 0xc1DB00a8E5Ef7bfa476395cdbcc98235477cDE4E "get_dx(int128,uint256[8],uint256,uint256,uint256[8],uint256[8],bool,int128,int128,uint256)(uint256)" 38237110009691290102777 "[8642515749474252628415,29731013613678119677889,0,0,0,0,0,0]" 100 4000000 "[0,0,0,0,0,0,0,0]" "[1000000000000000000,1000000000000000000,0,0,0,0,0,0]" true 1 0 1000000000000000000
