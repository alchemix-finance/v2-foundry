pragma solidity ^0.8.13;

import {IllegalState} from "../../base/Errors.sol";

import {IStakedFraxEth} from "../../interfaces/external/frax/IStakedFraxEth.sol";
import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";

import "../../libraries/TokenUtils.sol";

struct InitializationParams {
    address token;
    address underlyingToken;
}

/// @title  FraxEthAdapter
/// @author Alchemix Finance
contract FraxEthAdapter is ITokenAdapter {
    uint256 private constant MAXIMUM_SLIPPAGE = 10000;
    string public constant override version = "1.0.0";

    address public immutable override token;
    address public immutable override underlyingToken;

    constructor(InitializationParams memory params) {
        token = params.token;
        underlyingToken = params.underlyingToken;
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        return IStakedFraxEth(token).convertToAssets(1e18);
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, token, 0);
        TokenUtils.safeApprove(underlyingToken, token, amount);

        return IStakedFraxEth(token).deposit(amount, recipient);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        IStakedFraxEth(token).withdraw(amount * this.price() / 10**TokenUtils.expectDecimals(token), recipient, address(this));

        return TokenUtils.safeBalanceOf(underlyingToken, recipient);
    }
}