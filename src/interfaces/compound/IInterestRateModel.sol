// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

interface IInterestRateModel {
    function getBorrowRate(
        uint256,
        uint256,
        uint256
    ) external view returns (uint256);

    function getSupplyRate(
        uint256,
        uint256,
        uint256,
        uint256
    ) external view returns (uint256);
}