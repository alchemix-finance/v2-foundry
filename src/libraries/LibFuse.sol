// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";

import {ICERC20} from "../interfaces/external/compound/ICERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Get up to date cToken data without mutating state.
/// @author Transmissions11 (https://github.com/transmissions11/libcompound)
library LibFuse {
    using FixedPointMathLib for uint256;

    function viewUnderlyingBalanceOf(ICERC20 cToken, address user) internal view returns (uint256) {
        return cToken.balanceOf(user).mulWadDown(viewExchangeRate(cToken));
    }

    function viewExchangeRate(ICERC20 cToken) internal view returns (uint256) {
        uint256 accrualBlockNumberPrior = cToken.accrualBlockNumber();

        if (accrualBlockNumberPrior == block.number) return cToken.exchangeRateStored();

        uint256 totalCash = IERC20(cToken.underlying()).balanceOf(address(cToken));
        uint256 borrowsPrior = cToken.totalBorrows();
        uint256 reservesPrior = cToken.totalReserves();
        uint256 adminFeesPrior = cToken.totalAdminFees();
        uint256 fuseFeesPrior = cToken.totalFuseFees();

        uint256 interestAccumulated; // Generated in new scope to avoid stack too deep.
        {
            uint256 borrowRateMantissa = cToken.interestRateModel().getBorrowRate(
                totalCash,
                borrowsPrior,
                reservesPrior + adminFeesPrior + fuseFeesPrior
            );

            // Same as borrowRateMaxMantissa in CTokenInterfaces.sol
            require(borrowRateMantissa <= 0.0005e16, "RATE_TOO_HIGH");

            interestAccumulated = (borrowRateMantissa * (block.number - accrualBlockNumberPrior)).mulWadDown(
                borrowsPrior
            );
        }

        uint256 totalReserves = cToken.reserveFactorMantissa().mulWadDown(interestAccumulated) + reservesPrior;
        uint256 totalAdminFees = cToken.adminFeeMantissa().mulWadDown(interestAccumulated) + adminFeesPrior;
        uint256 totalFuseFees = cToken.fuseFeeMantissa().mulWadDown(interestAccumulated) + fuseFeesPrior;

        uint256 totalSupply = cToken.totalSupply();

        return
            totalSupply == 0
                ? cToken.initialExchangeRateMantissa()
                : (totalCash + (interestAccumulated + borrowsPrior) - (totalReserves + totalAdminFees + totalFuseFees))
                    .divWadDown(totalSupply);
    }
}