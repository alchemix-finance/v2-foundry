pragma solidity >= 0.8.13;

interface IFraxMinter {
    function depositEther(uint256 amount) external;
    function submitAndDeposit(address recipient) external payable returns (uint256);
    function submit() external payable;
}