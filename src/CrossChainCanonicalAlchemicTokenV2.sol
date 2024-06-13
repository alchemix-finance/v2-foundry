// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import {CrossChainCanonicalBase} from "./CrossChainCanonicalBase.sol";
import {AlchemicTokenV2Base} from "./AlchemicTokenV2Base.sol";

contract CrossChainCanonicalAlchemicTokenV2 is CrossChainCanonicalBase, AlchemicTokenV2Base {

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize(
      string memory name, 
      string memory symbol
  ) external initializer {
    __CrossChainCanonicalBase_init(
      name,
      symbol,
      msg.sender
    );
    __AlchemicTokenV2Base_init();
  }
}