// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ICurveFactoryethpool} from "./interfaces/ICurveFactoryethpool.sol";
import {IWETH9} from "./interfaces/external/IWETH9.sol";

import {AutoleverageBase} from "./AutoleverageBase.sol";

/// @title A zapper for leveraged deposits into the Alchemist
contract AutoleverageCurveFactoryethpool is AutoleverageBase {

    address public constant wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    /// @notice When the eth msg.value doesn't match the initialCollateral
    error IncorrectEthAmount();
    
    /// @notice Used to receive ETH from factory pool swaps
    receive() external payable {}

    function _transferTokensToSelf(address msgSender, uint msgValue, address underlyingToken, uint collateralInitial) internal override {
        // Convert eth to weth if received eth, otherwise transfer weth
        if (msgValue > 0) {
            if (msgValue != collateralInitial) revert IncorrectEthAmount();
            IWETH9(wethAddress).deposit{value: msgValue}();
        } else {
            IERC20(underlyingToken).transferFrom(msgSender, address(this), collateralInitial);
        }
    }

    function _maybeConvertCurveOutput(uint amountOut) internal override {
        // Convert ETH output from Curve into WETH
        IWETH9(wethAddress).deposit{value: amountOut}();
    }

    function _curveSwap(address poolAddress, address debtToken, int128 i, int128 j, uint256 minAmountOut) internal override returns (uint256 amountOut) {
        // Curve swap
        uint256 debtTokenBalance = IERC20(debtToken).balanceOf(address(this));
        IERC20(debtToken).approve(poolAddress, type(uint).max);
        return ICurveFactoryethpool(poolAddress).exchange(
            i,
            j,
            debtTokenBalance,
            minAmountOut
        );
    }

}