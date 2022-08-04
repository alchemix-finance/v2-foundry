// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

import {IVaultAdapter} from "./IVaultAdapter.sol";

interface IAlchemistV1 {
    function deposit(uint256 _amount) external;
    function migrate(IVaultAdapter _adapter) external;
    function mint(uint256 _amount) external;
    function setEmergencyExit(bool _emergencyExit) external;
    function flush() external returns (uint256);
    function getCdpTotalDeposited(address _account) external view returns (uint256);
    function getCdpTotalDebt(address _account) external view returns (uint256);
    function getVaultTotalDeposited(uint256 _vaultId) external view returns (uint256);
    function recall(uint256 _vaultId, uint256 _amount) external returns (uint256, uint256);
    function recallAll(uint256 _vaultId) external returns (uint256, uint256);
    function withdraw(uint256 _amount) external returns (uint256, uint256);
    function setTransmuter(address _transmuter) external;
    function liquidate(uint256 _amount) external returns (uint256, uint256);
    function harvest(uint256 _vaultId) external returns (uint256, uint256);
    function repay(uint256 _parentAmount, uint256 _childAmount) external;
    function vaultCount() external returns (uint256);
}