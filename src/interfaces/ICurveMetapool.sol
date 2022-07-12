pragma solidity ^0.8.13;

interface ICurveMetapool {
    /// @notice Perform an exchange between two underlying coins
    /// @dev Index values can be found via the `underlying_coins` public getter method
    /// @param i Index value for the underlying coin to send
    /// @param j Index valie of the underlying coin to recieve
    /// @param dx Amount of `i` being exchanged
    /// @param min_dy Minimum amount of `j` to receive
    /// @return Actual amount of `j` received
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
}

// interface ICurve {
//     function coins(uint256 i) external view returns (address);
//     function get_virtual_price() external view returns (uint256);
//     function calc_token_amount(uint256[] memory amounts, bool deposit) external view returns (uint256);
//     function calc_withdraw_one_coin(uint256 _token_amount, int128 i) external view returns (uint256);
//     function fee() external view returns (uint256);
//     function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
//     function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
//     function add_liquidity(uint256[] memory amounts, uint256 min_mint_amount) external;
//     function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_amount) external;
// }