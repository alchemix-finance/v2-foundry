// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IAlchemicToken} from "../../interfaces/IAlchemicToken.sol";
import {IConnext} from "../../interfaces/external/connext/IConnext.sol";
import {IXReceiver} from "../../interfaces/external/connext/IXReceiver.sol";

import "../../libraries/TokenUtils.sol";

/**
 * @title DestinationGreeterAuthenticated
 * @notice Example destination contract that stores a greeting and only allows source to update it.
 */
contract AlchemixConnextGateway is IXReceiver {
  /// @notice The admin.
  address public admin;

  // The Connext contract on this domain
  address public immutable connext;

  // The domain ID where the source contract is deployed
  mapping (uint32 => bool) public originDomains;

  // The address of the source contract
  mapping (address => bool) public sources;

  // The next tokens mapped to their respective alAssets. 
  mapping (address => address) public assets;

  /** @notice A modifier for authenticated calls.
   * This is an important security consideration. If the target contract
   * function should be authenticated, it must check three things:
   *    1) The originating call comes from the expected origin domain.
   *    2) The originating call comes from the expected source contract.
   *    3) The call to this contract comes from Connext.
   */
  modifier onlySource(address _originSender, uint32 _origin) {
    require(
      originDomains[_origin] &&
        sources[_originSender] &&
        msg.sender == connext,
      "Expected original caller to be source contract on origin domain and this to be called by Connext"
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

  function registerDomain(uint32 domain, bool active) external onlyAdmin {
    originDomains[domain] = active;
  }

  function registerSource(address source, bool active) external onlyAdmin {
    sources[source] = active;
  }

  function bridgeAssets (
    address target,
    address asset,
    address recipient,
    uint256 amount,
    uint32 destinationDomain,
    uint256 relayerFee
  ) external payable {
    // Transfer next tokens from alAsset contract and approve for spending.
    // Users can only bridge back the amount that was bridged over from mainnet.
    TokenUtils.safeTransferFrom(asset, assets[asset], address(this), amount);
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
  ) external onlySource(_originSender, _origin) returns (bytes memory) {
    // Mint alAssets 1:1 to user.
    IAlchemicToken(assets[_asset]).mint(abi.decode(_callData, (address)), _amount);    

    // Store nextAssets in alAsset as receipt for bridging back.
    TokenUtils.safeTransfer(_asset, assets[_asset], _amount);
  }
}