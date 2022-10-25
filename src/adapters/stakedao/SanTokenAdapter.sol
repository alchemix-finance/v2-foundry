pragma solidity ^0.8.11;

import {IllegalState} from "../../base/Errors.sol";

import "../../interfaces/ITokenAdapter.sol";
import "../../interfaces/external/stakedao/IAngleVault.sol";
import "../../interfaces/external/stakedao/ISanVault.sol";
import "../../interfaces/external/yearn/IYearnVaultV2.sol";

import "../../libraries/TokenUtils.sol";

/// @title  Stakedao San token adapter
/// @author Alchemix Finance
contract SanTokenAdapter is ITokenAdapter {
    uint256 private constant MAXIMUM_SLIPPAGE = 10000;
    string public constant override version = "2.1.0";

    address public immutable override token;
    address public immutable override underlyingToken;
    address public immutable poolManager;
    IAngleVault angleVault;
    ISanVault sanVault;

    constructor(address _token, address _underlyingToken, address _angleVault, address _poolManager, address _sanVault) {
        token = _token;
        underlyingToken = _underlyingToken;
        poolManager = _poolManager;
        angleVault = IAngleVault(_angleVault);
        sanVault = ISanVault(_sanVault);
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        // TODO
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, token, amount);

        angleVault.deposit(amount, recipient, poolManager);

        sanVault.deposit(recipient, TokenUtils.safeBalanceOf(token, address(this)), false);

        return TokenUtils.safeBalanceOf(token, address(this));
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        sanVault.withdraw(amount);

        angleVault.withdraw(TokenUtils.safeBalanceOf(token, address(this)), address(this), address(this), poolManager);

        uint256 amountWithdrawn = TokenUtils.safeBalanceOf(underlyingToken, address(this));

        TokenUtils.safeTransfer(underlyingToken, recipient, amountWithdrawn);

        return amountWithdrawn;
    }
}