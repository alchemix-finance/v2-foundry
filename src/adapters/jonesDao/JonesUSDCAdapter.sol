pragma solidity ^0.8.11;

import {IllegalState} from "../../base/Errors.sol";

import "../../interfaces/ITokenAdapter.sol";
import "../../libraries/TokenUtils.sol";
import "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {IJonesDaoGlpVault} from "../../interfaces/external/jones/IJonesDaoGlpVault.sol";
import {IJonesDaoVaultRouter} from "../../interfaces/external/jones/IJonesDaoVaultRouter.sol";
import {IJGLPViewer} from "../../interfaces/external/jones/IJGLPViewer.sol";

/// @title  JonesUSDCAdapter
/// @author Alchemix Finance
contract JonesUSDCAdapter is ITokenAdapter {
    uint256 private constant MAXIMUM_SLIPPAGE = 10000;
    string public constant override version = "1.0.0";

    address public immutable override token;
    address public immutable override underlyingToken;
    address public jonesGLPAdapter;
    address public jonesGLPVaultRouter;
    address public glpStableVault;
    address public jGLPViewer;

    constructor(address _glpAdapter, address _jglpViewer) {
        jonesGLPAdapter = _glpAdapter;
        jonesGLPVaultRouter = IJonesDaoGlpVault(_glpAdapter).vaultRouter();
        glpStableVault = IJonesDaoGlpVault(_glpAdapter).stableVault();
        jGLPViewer = _jglpViewer;
        underlyingToken = IERC4626(glpStableVault).asset();
        token = IJonesDaoVaultRouter(jonesGLPVaultRouter).rewardCompounder(underlyingToken);
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        (uint256 usdcRedemption,) = IJGLPViewer(jGLPViewer).getUSDCRedemption(1e18, address(this));
        return usdcRedemption;
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, jonesGLPAdapter, amount);
                
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IJonesDaoGlpVault(jonesGLPAdapter).depositStable(amount, true);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 receivedAmount = balanceAfter - balanceBefore;
        require(receivedAmount > 0, "no yieldToken received");
        TokenUtils.safeTransfer(token, recipient, receivedAmount);
        return receivedAmount;
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        uint256 balanceYieldTokenBefore = TokenUtils.safeBalanceOf(token, address(this));
        TokenUtils.safeApprove(token, jonesGLPVaultRouter, amount);

        uint256 balanceUnderlyingBefore = IERC20(underlyingToken).balanceOf(address(this));
        IJonesDaoVaultRouter(jonesGLPVaultRouter).stableWithdrawalSignal(amount,true);
        uint256 balanceUnderlyingAfter = IERC20(underlyingToken).balanceOf(address(this));
        uint256 receivedUnderlyingAmount = balanceUnderlyingAfter - balanceUnderlyingBefore;
        require(receivedUnderlyingAmount > 0, "no underlying withdrawn");
        TokenUtils.safeTransfer(underlyingToken, recipient, receivedUnderlyingAmount);

        uint256 balanceYieldTokenAfter = TokenUtils.safeBalanceOf(token, address(this));
        require(balanceYieldTokenBefore - balanceYieldTokenAfter == amount, "Unwrap failed");

        return receivedUnderlyingAmount;
    }
}