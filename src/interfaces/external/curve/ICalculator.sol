// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

int128 constant MAX_COINS = 8;
uint256 constant FEE_DENOMINATOR = 10**10;

interface ICalculator {
	function get_dx(
		int128 n_coins,
		uint256[MAX_COINS] calldata balances,
		uint256 amp,
		uint256 fee,
		uint256[MAX_COINS] calldata rates,
		uint256[MAX_COINS] calldata precisions,
		bool underlying,
		int128 i,
		int128 j,
		uint256 dy
	) external view returns (uint256);
}
