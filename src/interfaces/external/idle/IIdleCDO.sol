// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.7.0;

// import "../../IERC20Minimal.sol";
// import "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title  IIdleCDO
/// @author Idle Finance
interface IIdleCDO {
    function AATranche() external view returns (address);
    function BBTranche() external view returns (address);

    function strategy() external view returns (address);
    function strategyToken() external view returns (address);
    function token() external view returns (address);

    /// @notice Flag for allowing AA withdraws
    function allowAAWithdraw() external view returns (bool);

    /// @notice Flag for allowing BB withdraws
    function allowBBWithdraw() external view returns (bool);

    /// @param _tranche tranche address
    /// @return tranche price
    function tranchePrice(address _tranche) external view returns (uint256);

    /// @notice calculates the current tranches price considering the interest that is yet to be splitted
    /// ie the interest generated since the last update of priceAA and priceBB (done on depositXX/withdrawXX/harvest)
    /// useful for showing updated gains on frontends
    /// @dev this should always be >= of _tranchePrice(_tranche)
    /// @param _tranche address of the requested tranche
    /// @return _virtualPrice tranche price considering all interest
    function virtualPrice(address _tranche) external view returns (uint256);

    /// @notice pausable
    /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
    /// @param _amount amount of `token` to deposit
    /// @return AA tranche tokens minted
    function depositAA(uint256 _amount) external returns (uint256);

    /// @notice pausable
    /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
    /// @param _amount amount of `token` to deposit
    /// @return BB tranche tokens minted
    function depositBB(uint256 _amount) external returns (uint256);

    /// @notice pausable
    /// @param _amount amount of AA tranche tokens to burn
    /// @return underlying tokens redeemed
    function withdrawAA(uint256 _amount) external returns (uint256);

    /// @notice pausable
    /// @param _amount amount of BB tranche tokens to burn
    /// @return underlying tokens redeemed
    function withdrawBB(uint256 _amount) external returns (uint256);
}
