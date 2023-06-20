// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IAlchemicToken} from "../../interfaces/IAlchemicToken.sol";
import {IXReceiver} from "../../interfaces/external/connext/IXReceiver.sol";

/**
 * @title DestinationGreeterAuthenticated
 * @notice Example destination contract that stores a greeting and only allows source to update it.
 */
contract AlchemixL2Receiver is IXReceiver {
  // The Connext contract on this domain
  address public immutable connext;

  // The domain ID where the source contract is deployed
  uint32 public immutable originDomain;

  // The address of the source contract
  address public immutable source;

  /** @notice A modifier for authenticated calls.
   * This is an important security consideration. If the target contract
   * function should be authenticated, it must check three things:
   *    1) The originating call comes from the expected origin domain.
   *    2) The originating call comes from the expected source contract.
   *    3) The call to this contract comes from Connext.
   */
  modifier onlySource(address _originSender, uint32 _origin) {
    require(
      _origin == originDomain &&
        _originSender == source &&
        msg.sender == connext,
      "Expected original caller to be source contract on origin domain and this to be called by Connext"
    );
    _;
  }

  constructor(
    uint32 _originDomain,
    address _source,
    address _connext
  ) {
    originDomain = _originDomain;
    source = _source;
    connext = _connext;
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
    
    wrapFunds(abi.decode(_callData, (address)), _asset, _amount);
  }

  function wrapFunds(address recipient, address asset, uint256 amount) internal {
    // Mint alAssets to user.
    IAlchemicToken(asset).mint(recipient, amount);
  }
}