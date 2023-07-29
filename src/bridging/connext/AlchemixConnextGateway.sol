// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {ICrossChainToken} from "../../interfaces/ICrossChainToken.sol";
import {IConnext} from "../../interfaces/external/connext/IConnext.sol";
import {IXReceiver} from "../../interfaces/external/connext/IXReceiver.sol";

import "../../libraries/TokenUtils.sol";

/**
 * @title AlchemixConnextGateway
 */
contract AlchemixConnextGateway is IXReceiver {
  /// @notice The admin.
  address public admin;

  // The Connext contract on this domain
  address public immutable connext;

  // The next tokens mapped to their respective alAssets. 
  mapping (address => address) public assets;

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

  /// @dev A modifier which reverts if the message sender is not the admin.
  modifier onlyAdmin() {
      if (msg.sender != admin) {
          revert ("Not admin");
      }
      _;
  }

  constructor(
    address _connext
  ) {
    connext = _connext;
    admin = msg.sender;
  }

  function setAdmin(address newAdmin) external onlyAdmin {
    admin = newAdmin;
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
    ICrossChainToken(assets[_asset]).exchangeOldForCanonical(_asset, _amount);
    
    TokenUtils.safeTransfer(assets[_asset], abi.decode(_callData, (address)), _amount);
  }
}