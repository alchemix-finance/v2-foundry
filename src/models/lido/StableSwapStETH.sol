// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

uint256 constant N_COINS = 2;

contract StableSwapStETH {
	uint256 private ethPoolIndex;
	uint256 private stEthPoolIndex;

	uint256 private exchangeRate;
	uint256 private fee;

	address[N_COINS] coinAddress;

	constructor(address stEthAddress) {
		coinAddress[0] = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
		ethPoolIndex = 0;
		coinAddress[1] = stEthAddress;
		stEthPoolIndex = 1;
	}

	function getEthPoolIndex() external view returns (uint256) {
		return ethPoolIndex;
	}

	function getStEthPoolIndex() external view returns (uint256) {
		return stEthPoolIndex;
	}
	
    function coins(uint256 index) external view returns (address) {
		return coinAddress[index];
	}

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 minimumDy // ignored since WstETHAdapterV1 always calls with 0
	) external payable returns (uint256) {
		uint256 ui = uint256(int256(i));
		uint256 uj = uint256(int256(j));

		uint256 dy;
		
		if (ui == ethPoolIndex) {
			require(msg.value == dx);
			dy = dx * 10 ** 18 / exchangeRate;
		} else {
			IERC20(coinAddress[ui]).transferFrom(msg.sender, address(this), dx);
			dy = dx * exchangeRate / 10 ** 18;
		}

		uint256 dyFee = dy * fee / 10 ** 18;
		uint256 dyFinal = dy - dyFee;

		if (uj == ethPoolIndex) {
			require(msg.value == 0);
			(bool success, ) = msg.sender.call{value: dyFinal}("");
			require(success);
		} else {
			IERC20(coinAddress[uj]).transfer(msg.sender, dyFinal);
		}
		
		return dyFinal;
	}
}
