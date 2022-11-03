pragma solidity >= 0.8.13;

interface IFraxMinter {
    function submitAndDeposit(address recipient) external payable returns (uint256);
    function submit() external payable;
}