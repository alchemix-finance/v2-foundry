// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.12;

interface ITransferAdapter {
    function hasMigrated(address acct) external view returns (bool);
}