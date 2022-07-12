pragma solidity ^0.8.13;

contract HarvestResolverMock {
    uint256 public lastHarvest;
    constructor() {
        lastHarvest = block.timestamp;
    }

    function recordHarvest(address yieldToken) external {
        lastHarvest++;
    }
}
