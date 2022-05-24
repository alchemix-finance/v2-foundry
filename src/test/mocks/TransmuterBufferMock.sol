pragma solidity 0.8.13;

import "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IERC20TokenReceiver.sol";

contract TransmuterBufferMock is IERC20TokenReceiver {
    mapping(address => bool) public underlyingTokens;
    constructor(address underlyingToken) {
        underlyingTokens[underlyingToken] = true;
    }

    function onERC20Received(address underlyingToken, uint256 amount) external override {
        require(underlyingTokens[underlyingToken]);
    }
}