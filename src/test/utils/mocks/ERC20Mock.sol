// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 mockDecimals) ERC20(name, symbol) {
        _decimals = mockDecimals;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function burn(address owner, uint256 amount) public {
        _burn(owner, amount);
    }

    function mint(address receiver, uint256 amount) public {
        _mint(receiver, amount);
    }
}
