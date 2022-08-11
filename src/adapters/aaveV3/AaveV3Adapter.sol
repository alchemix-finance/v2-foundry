// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {IllegalState, Unauthorized} from "../../base/ErrorMessages.sol";
import {MutexLock} from "../../base/MutexLock.sol";
import {IERC20Minimal} from "../../interfaces/IERC20Minimal.sol";
import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IAaveV3Pool} from "../../interfaces/external/aave/IAaveV3Pool.sol";

import {TokenUtils} from "../../libraries/TokenUtils.sol";
import {console} from "../../../lib/forge-std/src/console.sol";


struct InitializationParams {
    address alchemist;
    address token;
    address underlyingToken;
    address pool;
    address oracle;
}

contract AaveV3Adapter is ITokenAdapter, MutexLock {
    string public constant override version = "1.0.0";
    address public alchemist;
    address public override token;
    address public override underlyingToken;
    address public pool;
    address public oracle;
    uint8 public tokenDecimals;

    constructor(InitializationParams memory params) {
        alchemist = params.alchemist;
        token = params.token;
        underlyingToken = params.underlyingToken;
        tokenDecimals = TokenUtils.expectDecimals(token);
        pool = params.pool;
        oracle = params.oracle;
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
        // In AAVE V3 depositing and withdrawing are expected to mint/burn the same amount of underlying/shares specified
        // Always a 1:1 ratio
        return 10**TokenUtils.expectDecimals(underlyingToken);
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external lock onlyAlchemist override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, pool, amount);

        // Does not return 
        IAaveV3Pool(pool).deposit(underlyingToken, amount, recipient, 0);

        return amount;
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external lock onlyAlchemist override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);
        TokenUtils.safeApprove(token, pool, amount);
        uint256 amountWithdrawn = IAaveV3Pool(pool).withdraw(underlyingToken, amount, recipient);

        return amount;
    }
} 