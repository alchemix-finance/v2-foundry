// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";


import {IConnext} from "../../interfaces/external/connext/IConnext.sol";

contract AlchemixL1Greeter {
  // The connext contract on the origin domain.
  IConnext public immutable connext;

  constructor(address _connext) {
    connext = IConnext(_connext);
  }

  function bridgeAssets (
    address target,
    address asset,
    address recipient,
    uint256 amount,
    uint32 destinationDomain,
    uint256 relayerFee
  ) external payable {
    IERC20 _token = IERC20(asset);
    
    // Transfer token from users and approve.
    _token.transferFrom(msg.sender, address(this), amount);
    _token.approve(address(connext), amount);


    // Encode the data needed for the target contract call.
    bytes memory callData = abi.encode(recipient);

    connext.xcall{value: relayerFee}(
      destinationDomain, // _destination
      target,            // _to
      asset,             // _asset
      msg.sender,        // _delegate
      amount,            // _amount
      0,                 // _slippage
      callData           // _callData
    );
  }
}