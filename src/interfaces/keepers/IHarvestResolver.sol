pragma solidity ^0.8.11;

interface IHarvestResolver {
    function recordHarvest(address yieldToken) external;
}
