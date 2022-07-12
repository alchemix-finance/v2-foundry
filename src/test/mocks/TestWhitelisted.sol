pragma solidity ^0.8.11;

import "../../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

import { Unauthorized } from "../../base/Errors.sol";

import "../../utils/Whitelist.sol";
import "../../interfaces/IWhitelist.sol";

contract TestWhitelisted is AccessControl {
  event Success();

  bytes32 public constant ADMIN = keccak256("ADMIN");
  address public whitelist;

  constructor(address _whitelist) {
    _setupRole(ADMIN, msg.sender);
    _setRoleAdmin(ADMIN, ADMIN);
    whitelist = _whitelist;
  }

  function test() external {
    // Check if the message sender is an EOA. In the future, this potentially may break. It is important that
    // functions which rely on the whitelist not be explicitly vulnerable in the situation where this no longer
    // holds true.
    if (tx.origin != msg.sender) {
      // Only check the whitelist for calls from contracts.
      if (!IWhitelist(whitelist).isWhitelisted(msg.sender)) {
        revert Unauthorized();
      }
    }
    emit Success();
  }
}
