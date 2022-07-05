pragma solidity ^0.8.11;

import "./TestWhitelisted.sol";

contract TestWhitelistedCaller {
    constructor() {

    }

    function test(address target) external {
        TestWhitelisted(target).test();
    }
}