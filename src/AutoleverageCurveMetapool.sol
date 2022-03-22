// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ICurveMetapool} from "./interfaces/ICurveMetapool.sol";

import {AutoleverageBase} from "./AutoleverageBase.sol";

/// @title A zapper for leveraged deposits into the Alchemist
contract AutoleverageCurveMetapool is AutoleverageBase {

    /// @notice When the eth msg.value is nonzero
    error IncorrectEthAmount();

    /// @inheritdoc AutoleverageBase
    function _transferTokensToSelf(address msgSender, uint msgValue, address underlyingToken, uint collateralInitial) internal override {
        if (msgValue > 0) revert IncorrectEthAmount();
        IERC20(underlyingToken).transferFrom(msg.sender, address(this), collateralInitial);
    }

    /// @inheritdoc AutoleverageBase
    function _maybeConvertCurveOutput(uint amountOut) internal override {}

    /// @inheritdoc AutoleverageBase
    function _curveSwap(address poolAddress, address debtToken, int128 i, int128 j, uint256 minAmountOut) internal override returns (uint256 amountOut) {
        // Curve swap
        uint256 debtTokenBalance = IERC20(debtToken).balanceOf(address(this));
        approve(debtToken, poolAddress);
        return ICurveMetapool(poolAddress).exchange_underlying(
            i,
            j,
            debtTokenBalance,
            minAmountOut
        );
    }
}