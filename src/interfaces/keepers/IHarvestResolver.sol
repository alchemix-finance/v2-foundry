pragma solidity ^0.8.13;

import "../../keepers/HarvestResolver.sol";

interface IHarvestResolver {
    function recordHarvest(address yieldToken) external;
    function harvestJobs(address yieldtoken) external returns (HarvestResolver.HarvestJob memory);
}
