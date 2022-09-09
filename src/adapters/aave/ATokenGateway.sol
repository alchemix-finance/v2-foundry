// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Ownable} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../..//base/ErrorMessages.sol";
import "../../interfaces/IAlchemistV2.sol";
import "../../interfaces/IATokenGateway.sol";
import "../../interfaces/IWhitelist.sol";
import "../../interfaces/external/aave/IStaticAToken.sol";
import "../../libraries/TokenUtils.sol";

/// @title  ATokenGateway
/// @author Alchemix Finance
contract ATokenGateway is IATokenGateway, Ownable {
    /// @notice The version.
    string public constant version = "1.0.1";

    /// @notice The address of the whitelist contract.
    address public override whitelist;

    /// @notice The address of the alchemist.
    address public override alchemist;

    constructor(address _whitelist, address _alchemist) {
        whitelist = _whitelist;
        alchemist = _alchemist;
    }

    /// @inheritdoc IATokenGateway
    function deposit(
        address yieldToken,
        uint256 amount,
        address recipient
    ) external override returns (uint256 sharesIssued) {
        _onlyWhitelisted();
        address aToken = address(IStaticAToken(yieldToken).ATOKEN());
        TokenUtils.safeTransferFrom(aToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(aToken, yieldToken, amount);
        // 0 - referral code (deprecated).
        // false - "from underlying", we are depositing the aToken, not the underlying token.
        uint256 staticATokensReceived = IStaticAToken(yieldToken).deposit(address(this), amount, 0, false);
        TokenUtils.safeApprove(yieldToken, alchemist, staticATokensReceived);
        return IAlchemistV2(alchemist).deposit(yieldToken, staticATokensReceived, recipient);
    }

    /// @inheritdoc IATokenGateway
    function withdraw(
        address yieldToken,
        uint256 shares,
        address recipient
    ) external override returns (uint256) {
        _onlyWhitelisted();
        uint256 staticATokensWithdrawn = IAlchemistV2(alchemist).withdrawFrom(msg.sender, yieldToken, shares, address(this));
        // false - "from underlying", we are depositing the aToken, not the underlying token.
        (uint256 amountBurnt, uint256 amountWithdrawn) = IStaticAToken(yieldToken).withdraw(recipient, staticATokensWithdrawn, false);
        if (amountBurnt != staticATokensWithdrawn) {
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