pragma solidity 0.8.13;


interface IPirexContract {
    function depositEther(address receiver, bool isCompound) external payable returns (uint256);
}