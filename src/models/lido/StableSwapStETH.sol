// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

uint256 constant N_COINS = 2;

contract StableSwapStETH {
	uint256 private ethPoolIndex;
	uint256 private stEthPoolIndex;

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
        uint256 minimumDy
	) external payable returns (uint256) {
		uint256 ui = uint256(int256(i));
		uint256 uj = uint256(int256(j));
		
		if (ui == ethPoolIndex) {
			require(msg.value == dx);
		} else {
			IERC20(coinAddress[ui]).transferFrom(msg.sender, address(this), dx);
		}

		if (uj == ethPoolIndex) {
			require(msg.value == 0);
			(bool success, ) = msg.sender.call{value: dx}("");
			require(success);
		} else {
			IERC20(coinAddress[uj]).transfer(msg.sender, dx);
		}
		
		return dx;
	}
}
