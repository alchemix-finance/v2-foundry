pragma solidity 0.8.13;

import "../../interfaces/IAlchemistV2.sol";

contract WhitelistedCaller {
    constructor() {}

    function makeAlchemistCall(address alchemist, address yieldToken, uint256 amount) external {
        IAlchemistV2(alchemist).depositUnderlying(yieldToken, amount, msg.sender, 0);
    } 
}