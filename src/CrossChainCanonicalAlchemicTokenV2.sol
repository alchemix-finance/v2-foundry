// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import {CrossChainCanonicalBase} from "./CrossChainCanonicalBase.sol";
import {AlchemicTokenV2Base} from "./AlchemicTokenV2Base.sol";

contract CrossChainCanonicalAlchemicTokenV2 is CrossChainCanonicalBase, AlchemicTokenV2Base {
  function initialize(
      string memory name, 
      string memory symbol, 
      address[] memory _bridgeTokens
  ) public initializer {
    __CrossChainCanonicalBase_init(
      name,
      symbol,
      msg.sender,
      _bridgeTokens
    );
    __AlchemicTokenV2Base_init();
  }
}
