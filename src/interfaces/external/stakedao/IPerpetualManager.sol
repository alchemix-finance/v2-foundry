// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "./IERC721.sol";
import "./IFeeManager.sol";
import "./IOracle.sol";
import "../../../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

/// @title Interface of the contract managing perpetuals
/// @author Angle Core Team
/// @dev Front interface, meaning only user-facing functions
interface IPerpetualManagerFront is IERC721Metadata {
    function openPerpetual(
        address owner,
        uint256 amountBrought,
        uint256 amountCommitted,
        uint256 maxOracleRate,
        uint256 minNetMargin
    ) external returns (uint256 perpetualID);

    function closePerpetual(
        uint256 perpetualID,
        address to,
        uint256 minCashOutAmount
    ) external;

    function addToPerpetual(uint256 perpetualID, uint256 amount) external;

    function removeFromPerpetual(
        uint256 perpetualID,
        uint256 amount,
        address to
    ) external;

    function liquidatePerpetuals(uint256[] memory perpetualIDs) external;

    function forceClosePerpetuals(uint256[] memory perpetualIDs) external;

    // ========================= External View Functions =============================

    function getCashOutAmount(uint256 perpetualID, uint256 rate) external view returns (uint256, uint256);

    function isApprovedOrOwner(address spender, uint256 perpetualID) external view returns (bool);
}

/// @title Interface of the contract managing perpetuals
/// @author Angle Core Team
/// @dev This interface does not contain user facing functions, it just has functions that are
/// interacted with in other parts of the protocol
interface IPerpetualManagerFunctions is IAccessControl {
    // ================================= Governance ================================

    function deployCollateral(
        address[] memory governorList,
        address guardian,
        IFeeManager feeManager,
        IOracle oracle_
    ) external;

    function setFeeManager(IFeeManager feeManager_) external;

    function setHAFees(
        uint64[] memory _xHAFees,
        uint64[] memory _yHAFees,
        uint8 deposit
    ) external;

    function setTargetAndLimitHAHedge(uint64 _targetHAHedge, uint64 _limitHAHedge) external;

    function setKeeperFeesLiquidationRatio(uint64 _keeperFeesLiquidationRatio) external;

    function setKeeperFeesCap(uint256 _keeperFeesLiquidationCap, uint256 _keeperFeesClosingCap) external;

    function setKeeperFeesClosing(uint64[] memory _xKeeperFeesClosing, uint64[] memory _yKeeperFeesClosing) external;

    function setLockTime(uint64 _lockTime) external;

    function setBoundsPerpetual(uint64 _maxLeverage, uint64 _maintenanceMargin) external;

    function pause() external;

    function unpause() external;

    // ==================================== Keepers ================================

    function setFeeKeeper(uint64 feeDeposit, uint64 feesWithdraw) external;

    // =============================== StableMaster ================================

    function setOracle(IOracle _oracle) external;
}

/// @title IPerpetualManager
/// @author Angle Core Team
/// @notice Previous interface with additionnal getters for public variables
interface IPerpetualManager is IPerpetualManagerFunctions {
    function poolManager() external view returns (address);

    function oracle() external view returns (address);

    function targetHAHedge() external view returns (uint64);

    function totalHedgeAmount() external view returns (uint256);
}

/// @title Interface of the contract managing perpetuals with claim function
/// @author Angle Core Team
/// @dev Front interface with rewards function, meaning only user-facing functions
interface IPerpetualManagerFrontWithClaim is IPerpetualManagerFront, IPerpetualManager {
    function getReward(uint256 perpetualID) external;
}