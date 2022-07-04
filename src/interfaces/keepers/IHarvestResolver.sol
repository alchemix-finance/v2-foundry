pragma solidity ^0.8.13;

interface IHarvestResolver {
    function recordHarvest(address yieldToken) external;
}
