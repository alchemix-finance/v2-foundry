// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title IJonesWhitelist
interface IJonesWhitelist {
    struct RoleInfo {
        bool BYPASS_COOLDOWN;
        uint256 INCENTIVE_RETENTION;
    }

    function getUSDCRedemption(uint256 _jUSDC, address _caller) external view returns (uint256, uint256);
    function addToWhitelist(address _account) external;
    function createRole(bytes32 _roleName, RoleInfo memory _roleInfo) external;
    function addToRole(bytes32 ROLE, address _account) external;
}