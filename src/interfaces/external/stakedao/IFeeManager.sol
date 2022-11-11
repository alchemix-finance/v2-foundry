// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "../../../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

/// @title IFeeManagerFunctions
/// @author Angle Core Team
/// @dev Interface for the `FeeManager` contract
interface IFeeManagerFunctions is IAccessControl {
    // ================================= Keepers ===================================

    function updateUsersSLP() external;

    function updateHA() external;

    // ================================= Governance ================================

    function deployCollateral(
        address[] memory governorList,
        address guardian,
        address _perpetualManager
    ) external;

    function setFees(
        uint256[] memory xArray,
        uint64[] memory yArray,
        uint8 typeChange
    ) external;

    function setHAFees(uint64 _haFeeDeposit, uint64 _haFeeWithdraw) external;
}

/// @title IFeeManager
/// @author Angle Core Team
/// @notice Previous interface with additionnal getters for public variables and mappings
/// @dev We need these getters as they are used in other contracts of the protocol
interface IFeeManager is IFeeManagerFunctions {
    function stableMaster() external view returns (address);

    function perpetualManager() external view returns (address);
}