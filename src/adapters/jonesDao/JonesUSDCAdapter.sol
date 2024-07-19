pragma solidity ^0.8.11;

import {IllegalState} from "../../base/Errors.sol";

import "../../interfaces/ITokenAdapter.sol";
import "../../libraries/TokenUtils.sol";
import "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {IJonesDaoGlpVault} from "../../interfaces/external/jones/IJonesDaoGlpVault.sol";
import {IJonesDaoVaultRouter} from "../../interfaces/external/jones/IJonesDaoVaultRouter.sol";
import {IJonesStableVault} from "../../interfaces/external/jones/IJonesStableVault.sol";
import {IJGLPViewer} from "../../interfaces/external/jones/IJGLPViewer.sol";

/// @title  JonesUSDCAdapter
/// @author Alchemix Finance
contract JonesUSDCAdapter is ITokenAdapter {
    string public constant override version = "1.0.0";

    address public immutable override token;
    address public immutable override underlyingToken;
    address public jonesGLPVaultRouter;

    constructor(address _glpRouter, address _underlying, address _vault) {
        jonesGLPVaultRouter = _glpRouter;
        underlyingToken = _underlying;
        token = _vault;
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        return IJonesStableVault(token).convertToAssets(1e18);
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, jonesGLPVaultRouter, amount);
                
        uint256 shares = IJonesDaoVaultRouter(jonesGLPVaultRouter).deposit(amount, recipient);

        return shares;
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);
        TokenUtils.safeApprove(token, jonesGLPVaultRouter, amount);

        (bool bypass, uint256 shares) = IJonesDaoVaultRouter(jonesGLPVaultRouter).withdrawRequest(amount, recipient, this.price() * amount * 9800 / 10000, "");

         require(bypass == true, "Withrawal queue not bypassed!");

         return shares;
    }
}