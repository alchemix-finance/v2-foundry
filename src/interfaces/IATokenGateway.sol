pragma solidity 0.8.13;

interface IATokenGateway {
    function deposit(address alchemist, address aToken, address staticAToken, uint256 amount, address recipient) external returns (uint256 sharesIssued);
    function withdraw(address alchemist, address aToken, address staticAToken, uint256 amouutn, address recipient) external returns (uint256 amountWithdrawn);
}