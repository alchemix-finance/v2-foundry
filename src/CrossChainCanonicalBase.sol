// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import {ERC20PermitUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

import {IllegalArgument, IllegalState} from "./base/Errors.sol";

import {TokenUtils} from "./libraries/TokenUtils.sol";

contract CrossChainCanonicalBase is ERC20PermitUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    /* ========== INITIALIZER ========== */

    function __CrossChainCanonicalBase_init(
        string memory _name,
        string memory _symbol,
        address _creatorAddress
    ) internal {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __EIP712_init_unchained(_name, "1");
        __ERC20_init_unchained(_name, _symbol);
        __ERC20Permit_init_unchained(_name);
        __ReentrancyGuard_init_unchained(); // Note: this is called here but not in AlchemicTokenV2Base. Careful if inheriting that without this
        _transferOwnership(_creatorAddress);
    }
}