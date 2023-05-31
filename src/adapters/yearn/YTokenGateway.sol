// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Ownable} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../..//base/ErrorMessages.sol";
import "../../interfaces/IAlchemistV2.sol";
import "../../interfaces/ITokenGateway.sol";
import "../../interfaces/IWhitelist.sol";
import "../../interfaces/external/yearn/IYearnStakingToken.sol";
import "../../libraries/TokenUtils.sol";

/// @title  YTokenGateway
/// @author Alchemix Finance
contract YTokenGateway is ITokenGateway, Ownable {
    /// @notice The version.
    string public constant version = "1.0.0";

    /// @notice The address of the whitelist contract.
    address public override immutable whitelist;

    /// @notice The address of the alchemist.
    address public override immutable alchemist;

    constructor(address _whitelist, address _alchemist) {
        whitelist = _whitelist;
        alchemist = _alchemist;
    }

    /// @inheritdoc ITokenGateway
    function deposit(
        address yieldToken,
        uint256 amount,
        address recipient
    ) external override returns (uint256 sharesIssued) {
        _onlyWhitelisted();
        address yToken = address(IYearnStakingToken(yieldToken).YEARN_VAULT());
        TokenUtils.safeTransferFrom(yToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(yToken, yieldToken, amount);
        // 0 - referral code (deprecated).
        // false - "from underlying", we are depositing the staking token, not the underlying token.
        uint256 staticYTokensReceived = IYearnStakingToken(yieldToken).deposit(address(this), amount, false);
        TokenUtils.safeApprove(yieldToken, alchemist, staticYTokensReceived);
        return IAlchemistV2(alchemist).deposit(yieldToken, staticYTokensReceived, recipient);
    }

    /// @inheritdoc ITokenGateway
    function withdraw(
        address yieldToken,
        uint256 shares,
        address recipient
    ) external override returns (uint256) {
        _onlyWhitelisted();
        uint256 staticYTokensWithdrawn = IAlchemistV2(alchemist).withdrawFrom(msg.sender, yieldToken, shares, address(this));
        // false - "from underlying", we are depositing the staking token, not the underlying token.
        (uint256 amountBurnt, uint256 amountWithdrawn) = IYearnStakingToken(yieldToken).withdraw(recipient, staticYTokensWithdrawn, 0, false); // Slippage handled upstream
        if (amountBurnt != staticYTokensWithdrawn) {
            revert IllegalState("not enough burnt");
        }
        return amountWithdrawn;
    }

    /// @dev Checks the whitelist for msg.sender.
    ///
    /// Reverts if msg.sender is not in the whitelist.
    function _onlyWhitelisted() internal view {
        // Check if the message sender is an EOA. In the future, this potentially may break. It is important that functions
        // which rely on the whitelist not be explicitly vulnerable in the situation where this no longer holds true.
        if (tx.origin == msg.sender) {
            return;
        }

        // Only check the whitelist for calls from contracts.
        if (!IWhitelist(whitelist).isWhitelisted(msg.sender)) {
            revert Unauthorized("Not whitelisted");
        }
    }
}