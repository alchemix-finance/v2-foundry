// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ICurveFactoryethpool} from "./interfaces/ICurveFactoryethpool.sol";
import {IWETH9} from "./interfaces/external/IWETH9.sol";

import {AutoleverageBase} from "./AutoleverageBase.sol";

/// @title A zapper for leveraged deposits into the Alchemist
contract AutoleverageCurveFactoryethpool is AutoleverageBase {

    address public constant wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    /// @notice Used to receive ETH from factory pool swaps
    receive() external payable {}

    /// @inheritdoc AutoleverageBase
    function _transferTokensToSelf(address underlyingToken, uint256 collateralInitial) internal override {
        // Convert eth to weth if received eth, otherwise transfer weth
        if (msg.value > 0) {
            if (msg.value != collateralInitial) revert IllegalArgument("msg.value doesn't match collateralInitial");
            IWETH9(wethAddress).deposit{value: msg.value}();
        } else {
            IERC20(underlyingToken).transferFrom(msg.sender, address(this), collateralInitial);
        }
    }

    /// @inheritdoc AutoleverageBase
    function _maybeConvertCurveOutput(uint256 amountOut) internal override {
        // Convert ETH output from Curve into WETH
        IWETH9(wethAddress).deposit{value: amountOut}();
    }

    /// @inheritdoc AutoleverageBase
    function _curveSwap(address poolAddress, address debtToken, int128 i, int128 j, uint256 minAmountOut) internal override returns (uint256 amountOut) {
        // Curve swap
        uint256 debtTokenBalance = IERC20(debtToken).balanceOf(address(this));
        approve(debtToken, poolAddress);
        return ICurveFactoryethpool(poolAddress).exchange(
            i,
            j,
            debtTokenBalance,
            minAmountOut
        );
    }

}