// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AccessControlUpgradeable} from "../../../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {OwnableUpgradeable} from "../../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {ICrossChainToken} from "../../interfaces/ICrossChainToken.sol";
import {IConnext} from "../../interfaces/external/connext/IConnext.sol";
import {IXReceiver} from "../../interfaces/external/connext/IXReceiver.sol";

import "../../libraries/TokenUtils.sol";

import {IllegalArgument, IllegalState, Unauthorized} from "./../../base/Errors.sol";

struct InitializationParams {
  address connext;
}

/**
 * @title AlchemixConnextGateway
 */
contract AlchemixConnextGateway is IXReceiver, AccessControlUpgradeable, OwnableUpgradeable {
  /// @notice The identifier of the role which maintains other roles.
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

  /// @notice The identifier of the role which allows accounts to mint tokens.
  bytes32 public constant SENTINEL_ROLE = keccak256("SENTINEL");

  /// @notice A set of addresses which are whitelisted for minting new tokens.
  mapping(address => bool) public whitelisted;

  // The Connext contract on this domain
  address public connext;

  // The next tokens mapped to their respective alAssets. 
  mapping (address => address) public assets;

  // @notice Emitted when tokens are bridged to layer 2
  event TokensReceived(bytes32 transferId, address originSender, uint32 origin, address token, address receiver, uint256 amount);

  constructor() initializer {}

  function initialize(InitializationParams memory params) public initializer {
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(SENTINEL_ROLE, msg.sender);
    _setRoleAdmin(SENTINEL_ROLE, ADMIN_ROLE);
    _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);

    __Context_init_unchained();
    __Ownable_init_unchained();

    connext = params.connext;
  }

  /// @dev A modifier which checks that the caller has the admin role.
  modifier onlyAdmin() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      revert Unauthorized();
    }
    _;
  }
  /** @notice A modifier for authenticated calls.
   * This is an important security consideration. msg.sender must be the connext contract.
   */
  modifier onlySource() {
    require(
        msg.sender == connext,
      "Expected original caller to be Connext contract"
    );
    _;
  }
  
  function registerAsset(address nextAsset, address alAsset) external onlyAdmin {
    assets[nextAsset] = alAsset;
  }

  function bridgeAssets (
    address _target,
    address _asset,
    uint256 _amount,
    uint32 _destinationDomain,
    uint256 _relayerFee,
    bytes calldata _callData
  ) external payable returns (bytes32) {
    TokenUtils.safeTransferFrom(assets[_asset], _target, address(this), _amount);
    ICrossChainToken(assets[_asset]).exchangeCanonicalForOld(_asset, _amount);

    TokenUtils.safeApprove(_asset, connext, _amount);
    return IConnext(connext).xcall{value: _relayerFee}(
      _destinationDomain, // _destination
      _target,            // _to
      _asset,             // _asset
      msg.sender,         // _delegate
      _amount,            // _amount
      10000,              // _slippage
      _callData           // _callData
    );
  }

  /** @notice Authenticated receiver function.
    * @param _callData Calldata containing the new greeting.
    */
  function xReceive(
    bytes32 _transferId,
    uint256 _amount,
    address _asset,
    address _originSender,
    uint32 _origin,
    bytes memory _callData
  ) external onlySource() returns (bytes memory) {
    TokenUtils.safeApprove(_asset, assets[_asset], _amount);

    try ICrossChainToken(assets[_asset]).exchangeOldForCanonical(_asset, _amount) {
      TokenUtils.safeTransfer(assets[_asset], abi.decode(_callData, (address)), _amount);

      emit TokensReceived(_transferId, _originSender, _origin, assets[_asset], abi.decode(_callData, (address)), _amount);
    } catch {
      TokenUtils.safeTransfer(_asset, abi.decode(_callData, (address)), _amount);
      
      emit TokensReceived(_transferId, _originSender, _origin, _asset, abi.decode(_callData, (address)), _amount);
    }    
  }
}