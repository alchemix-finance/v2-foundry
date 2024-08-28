pragma solidity 0.8.13;

import {IllegalState} from "../../base/Errors.sol";

import "../../interfaces/ITokenAdapter.sol";
import "../../interfaces/external/yearn/IYearnStakingToken.sol";
import "../../interfaces/external/yearn/IYearnVaultV2.sol";


import "../../libraries/TokenUtils.sol";

/// @title  YearnTokenAdapter for Optimism
/// @author Alchemix Finance
contract YearnTokenAdapterOptimism is ITokenAdapter {
    uint256 private constant MAXIMUM_SLIPPAGE = 10000;
    string public constant override version = "1.0.0";

    address public immutable override token;
    address public immutable override underlyingToken;

    constructor(address _token, address _underlyingToken) {
        token = _token;
        underlyingToken = _underlyingToken;
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        return IYearnVaultV2(address(IYearnStakingToken(token).YEARN_VAULT())).pricePerShare();
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, token, 0);
        TokenUtils.safeApprove(underlyingToken, token, amount);

        return IYearnStakingToken(token).deposit(recipient, amount, true);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        uint256 balanceBefore = TokenUtils.safeBalanceOf(token, address(this));

        (, uint256 amountWithdrawn) = IYearnStakingToken(token).withdraw(recipient, amount, MAXIMUM_SLIPPAGE, true);

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