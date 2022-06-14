pragma solidity ^0.8.13;

import {IllegalState, Unauthorized} from "../../base/ErrorMessages.sol";

import {IERC20Metadata} from "../../interfaces/IERC20Metadata.sol";
import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IStaticAToken} from "../../interfaces/external/aave/IStaticAToken.sol";

import {TokenUtils} from "../../libraries/TokenUtils.sol";

struct InitializationParams {
    address alchemist;
    address token;
    address underlyingToken;
}

contract AAVETokenAdapter is ITokenAdapter {
    string public constant override version = "1.0.0";
    address public alchemist;
    address public override token;
    address public override underlyingToken;

    constructor(InitializationParams memory params) {
        alchemist = params.alchemist;
        token = params.token;
        underlyingToken = params.underlyingToken;
    }

    /// @dev Checks that the message sender is the alchemist that the adapter is bound to.
    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert Unauthorized("Not alchemist");
        }
        _;
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        return IStaticAToken(token).staticToDynamicAmount(10**TokenUtils.expectDecimals(token));
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, token, amount);
        return IStaticAToken(token).deposit(recipient, amount, 0, true);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);
        (uint256 amountBurnt, uint256 amountWithdrawn) = IStaticAToken(token).withdraw(recipient, amount, true);
        if (amountBurnt != amount) {
           revert IllegalState("Amount burnt mismatch");
        }
        return amountWithdrawn;
    }
} 