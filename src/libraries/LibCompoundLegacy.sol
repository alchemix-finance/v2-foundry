// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {IllegalState} from "../base/Errors.sol";

import {FixedPointMathLib} from "./solmate/FixedPointMathLib.sol";

import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {ICERC20Legacy} from "../interfaces/compound/ICERC20Legacy.sol";

/// @notice Get up to date cToken data without mutating state.
/// @author Transmissions11 (https://github.com/transmissions11/libcompound)
library LibCompoundLegacy {
    using FixedPointMathLib for uint256;

    function viewUnderlyingBalanceOf(ICERC20Legacy cToken, address user) internal view returns (uint256) {
        return cToken.balanceOf(user).mulWadDown(viewExchangeRate(cToken));
    }

    function viewExchangeRate(ICERC20Legacy cToken) internal view returns (uint256) {
        uint256 accrualBlockNumberPrior = cToken.accrualBlockNumber();

        if (accrualBlockNumberPrior == block.number) return cToken.exchangeRateStored();

        uint256 totalCash = IERC20Minimal(cToken.underlying()).balanceOf(address(cToken));
        uint256 borrowsPrior = cToken.totalBorrows();
        uint256 reservesPrior = cToken.totalReserves();

        (uint256 err, uint256 borrowRateMantissa) = cToken.interestRateModel().getBorrowRate(totalCash, borrowsPrior, reservesPrior);

        if (borrowRateMantissa > 0.0005e16) {
            revert IllegalState();
        }

        uint256 interestAccumulated = (borrowRateMantissa * (block.number - accrualBlockNumberPrior)).mulWadDown(
            borrowsPrior
        );

        uint256 totalReserves = cToken.reserveFactorMantissa().mulWadDown(interestAccumulated) + reservesPrior;
        uint256 totalBorrows = interestAccumulated + borrowsPrior;
        uint256 totalSupply = cToken.totalSupply();

        return totalSupply == 0
            ? cToken.initialExchangeRateMantissa()
            : (totalCash + totalBorrows - totalReserves).divWadDown(totalSupply);
    }
}