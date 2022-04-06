pragma solidity >=0.5.0;

interface IStargateRouter {
    function addLiquidity(uint256 poolId, uint256 amount, address to) external;
    function instantRedeemLocal(uint16 poolId, uint256 amount, address to) external;
}