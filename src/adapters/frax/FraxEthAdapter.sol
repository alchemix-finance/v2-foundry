pragma solidity ^0.8.13;

import {IllegalState} from "../../base/Errors.sol";

import "../../interfaces/ITokenAdapter.sol";
import "../../interfaces/external/frax/IFraxEth.sol";
import "../../interfaces/external/frax/IStakedFraxEth.sol";

import "../../libraries/TokenUtils.sol";

struct InitializationParams {
    address stakingToken;
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
    address public immutable stakingToken;

    constructor(InitializationParams memory params) {
        stakingToken = params.stakingToken;
        token = params.token;
        underlyingToken = params.underlyingToken;
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        return 0;
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, token, 0);
        TokenUtils.safeApprove(underlyingToken, token, amount);

        IFraxEth(token).minter_mint(address(this), amount);

        return IStakedFraxEth(stakingToken).deposit(amount, recipient);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        uint256 balanceBefore = TokenUtils.safeBalanceOf(token, address(this));

        uint256 amountWithdrawn = IStakedFraxEth(stakingToken).withdraw(amount, address(this), recipient);
        IFraxEth(token).minter_burn_from(address(this), amountWithdrawn);

        uint256 balanceAfter = TokenUtils.safeBalanceOf(token, address(this));

        // If the Yearn vault did not burn all of the shares then revert. This is critical in mathematical operations
        // performed by the system because the system always expects that all of the tokens were unwrapped. In Yearn,
        // this sometimes does not happen in cases where strategies cannot withdraw all of the requested tokens (an
        // example strategy where this can occur is with Compound and AAVE where funds may not be accessible because
        // they were lent out).
        if (balanceBefore - balanceAfter != amount) {
            revert IllegalState();
        }

        return amountWithdrawn;
    }
}