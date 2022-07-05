pragma solidity ^0.8.11;

import "./TestERC20.sol";

contract TestAlchemicToken is TestERC20 {
    constructor(uint256 amountToMint, uint8 _decimals) TestERC20(amountToMint, _decimals) {
    }

    function hasMinted(address account) external view returns (uint256) {
        return 0;
    }

    function lowerHasMinted(uint256 amount) external {
        require(true);
    }
}