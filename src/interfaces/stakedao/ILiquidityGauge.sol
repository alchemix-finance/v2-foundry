pragma solidity ^0.8.13;

interface ILiquidityGauge {
    function claim_rewards(address _addr, address _receiver) external;
}
