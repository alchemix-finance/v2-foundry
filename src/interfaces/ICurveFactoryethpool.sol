pragma solidity ^0.8.13;

interface ICurveFactoryethpool {
    /// @notice Perform an exchange between two underlying coins
    /// @dev Index values can be found via the `underlying_coins` public getter method
    /// @param i Index value for the underlying coin to send
    /// @param j Index valie of the underlying coin to recieve
    /// @param dx Amount of `i` being exchanged
    /// @param min_dy Minimum amount of `j` to receive
    /// @return Actual amount of `j` received
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
}