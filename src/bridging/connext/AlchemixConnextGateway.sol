// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IAlchemicToken} from "../../interfaces/IAlchemicToken.sol";
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
    address target,
    address asset,
    address recipient,
    uint256 amount,
    uint32 destinationDomain,
    uint256 relayerFee
  ) external payable {
    // Approve next assets for connext burning.
    TokenUtils.safeApprove(asset, connext, amount);

    // Burn alAssets from user.
    IAlchemicToken(assets[asset]).burnFrom(msg.sender, amount);

    // Encode the data needed for the target contract call.
    bytes memory callData = abi.encode(recipient);

    IConnext(connext).xcall{value: relayerFee}(
      destinationDomain, // _destination
      target,            // _to
      asset,             // _asset
      msg.sender,        // _delegate
      amount,            // _amount
      0,                 // _slippage
      callData           // _callData
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
    // Mint alAssets 1:1 to user.
    IAlchemicToken(assets[_asset]).mint(abi.decode(_callData, (address)), _amount);    
  }
}