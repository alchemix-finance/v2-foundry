pragma solidity ^0.8.11;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ITokenAdapter.sol";
import "../interfaces/test/ITestYieldToken.sol";

import "../libraries/TokenUtils.sol";

/// @title  TestYieldTokenAdapter
/// @author Alchemix Finance
contract TestYieldTokenAdapter is ITokenAdapter {
    string public constant override version = "2.0.0";
    
    /// @inheritdoc ITokenAdapter
    address public immutable override token;

    /// @inheritdoc ITokenAdapter
    address public immutable override underlyingToken;

    constructor(address _token) {
        token = _token;
        underlyingToken = ITestYieldToken(_token).underlyingToken();
        IERC20(ITestYieldToken(_token).underlyingToken()).approve(_token, type(uint256).max);
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        return ITestYieldToken(token).price();
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        return ITestYieldToken(token).mint(amount, recipient);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);
        return ITestYieldToken(token).redeem(amount, recipient);
    }
}
