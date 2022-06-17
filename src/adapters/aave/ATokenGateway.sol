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
    string public constant version = "1.0.0";

    /// @notice The address of the whitelist contract.
    address public override whitelist;

    constructor(address _whitelist) {
        whitelist = _whitelist;
    }

    /// @inheritdoc IATokenGateway
    function deposit(
        address alchemist,
        address aToken,
        address staticAToken,
        uint256 amount,
        address recipient
    ) external override returns (uint256 sharesIssued) {
        _onlyWhitelisted();
        TokenUtils.safeTransferFrom(aToken, msg.sender, address(this), amount);
        uint256 depositedAmount = IStaticAToken(staticAToken).deposit(recipient, amount, 0, false);
        return IAlchemistV2(alchemist).deposit(staticAToken, depositedAmount, recipient);
    }

    /// @inheritdoc IATokenGateway
    function withdraw(
        address alchemist,
        address aToken,
        address staticAToken,
        uint256 shares,
        address recipient
    ) external override returns (uint256 amountWithdrawn) {
        _onlyWhitelisted();
        uint256 staticATokensWithdrawn = IAlchemistV2(alchemist).withdrawFrom(msg.sender, staticAToken, shares, address(this));
        (uint256 amountBurnt, uint256 amountWithdrawn) = IStaticAToken(staticAToken).withdraw(msg.sender, amountWithdrawn, false);
        if (amountBurnt != amountWithdrawn) {
            revert IllegalState("not enough burnt");
        }
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