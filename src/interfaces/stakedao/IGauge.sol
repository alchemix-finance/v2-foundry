pragma solidity ^0.8.13;

interface IGauge {
    function user_checkpoint(address addr) external returns (bool);
}