pragma solidity >= 0.8.13;

interface IFraxEth {
    function minter_mint(address m_address, uint256 m_amount) external;

    function minter_burn_from(address b_address, uint256 b_amount) external;
}