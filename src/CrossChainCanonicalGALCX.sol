// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import {CrossChainCanonicalBase} from "./CrossChainCanonicalBase.sol";

contract CrossChainCanonicalGALCX is CrossChainCanonicalBase {

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize(
      string memory name, 
      string memory symbol, 
      address[] memory _bridgeTokens,
      uint256[] memory _mintCeilings
  ) external initializer {
    __CrossChainCanonicalBase_init(
      name,
      symbol,
      msg.sender,
      _bridgeTokens,
      _mintCeilings
    );
  }
}