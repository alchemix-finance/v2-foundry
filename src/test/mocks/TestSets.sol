pragma solidity ^0.8.11;

import "../../libraries/Sets.sol";

contract TestSets {
    using Sets for Sets.AddressSet;

    Sets.AddressSet private testAddys;

    constructor() {

    }

    function add(address val) external {
        require(testAddys.add(val), "failed to add");
    }

    function remove(address val) external {
        require(testAddys.remove(val), "failed to remove");
    }

    function contains(address val) external view returns (bool) {
        return testAddys.contains(val);
    }
}