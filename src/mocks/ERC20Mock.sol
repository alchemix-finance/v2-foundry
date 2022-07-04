// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.13;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title ERC20Mock
///
/// @dev A mock of an ERC20 token which lets anyone burn and mint tokens.
contract ERC20Mock is ERC20 {
    constructor(string memory _name, string memory _symbol)
        public
        ERC20(_name, _symbol)
    {}

    function mint(address _recipient, uint256 _amount) external {
        _mint(_recipient, _amount);
    }

    function burn(address _account, uint256 _amount) external {
        _burn(_account, _amount);
    }
}
