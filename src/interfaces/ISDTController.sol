pragma solidity ^0.8.13;

interface ISDTController {
    function voteForGaugeWeights(address gaugeAddress, uint256 weight) external;
}