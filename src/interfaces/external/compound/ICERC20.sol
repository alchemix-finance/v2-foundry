// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {IERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IInterestRateModel} from "./IInterestRateModel.sol";

interface ICERC20 is IERC20 {
    function mint(uint256) external returns (uint256);

    function borrow(uint256) external returns (uint256);

    function underlying() external view returns (address);

    function totalBorrows() external view returns (uint256);

    function totalFuseFees() external view returns (uint256);

    function repayBorrow(uint256) external returns (uint256);

    function totalReserves() external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function totalAdminFees() external view returns (uint256);

    function fuseFeeMantissa() external view returns (uint256);

    function adminFeeMantissa() external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function accrualBlockNumber() external view returns (uint256);

    function redeemUnderlying(uint256) external returns (uint256);

    function redeem(uint redeemTokens) external returns (uint);

    function balanceOfUnderlying(address) external returns (uint256);

    function reserveFactorMantissa() external view returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function interestRateModel() external view returns (IInterestRateModel);

    function initialExchangeRateMantissa() external view returns (uint256);

    function repayBorrowBehalf(address, uint256) external returns (uint256);
}