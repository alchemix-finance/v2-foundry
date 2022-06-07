pragma solidity 0.8.13;

import "../../interfaces/IAlchemistV2.sol";
import "../../interfaces/IERC20Mintable.sol";

contract WhitelistedCaller {
    constructor() {}

    function makeAlchemistCall(address alchemist, address yieldToken, uint256 amount) external {
        IERC20Mintable(yieldToken).approve(alchemist, amount);
        IAlchemistV2(alchemist).deposit(yieldToken, amount, msg.sender);
    } 
}