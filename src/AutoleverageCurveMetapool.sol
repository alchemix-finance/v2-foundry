// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ICurveMetapool} from "./interfaces/ICurveMetapool.sol";

import {AutoleverageBase} from "./AutoleverageBase.sol";

/// @title A zapper for leveraged deposits into the Alchemist
contract AutoleverageCurveMetapool is AutoleverageBase {

    /// @inheritdoc AutoleverageBase
    function _transferTokensToSelf(address underlyingToken, uint256 collateralInitial) internal override {
        if (msg.value > 0) revert IllegalArgument("msg.value should be 0");
        IERC20(underlyingToken).transferFrom(msg.sender, address(this), collateralInitial);
    }

    /// @inheritdoc AutoleverageBase
    function _maybeConvertCurveOutput(uint256 amountOut) internal override {}

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