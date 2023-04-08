pragma solidity ^0.8.13;

interface IGaugeController {
    function vote_for_gauge_weight(address gaugeAddress, uint256 weight) external;
}