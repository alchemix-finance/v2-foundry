pragma solidity ^0.8.13;

import {IYieldToken} from "../interfaces/IYieldToken.sol";

contract TokenAdapterMock {
    address public token;

    constructor(address _token) {
        token = _token;
    }

    function price() external view returns (uint256) {
        return IYieldToken(token).price();
    }
}
