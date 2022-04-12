// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {EthAssetManager} from "../../../EthAssetManager.sol";

contract EthAssetManagerUser {
    EthAssetManager internal manager;

    constructor(EthAssetManager _manager) { manager = _manager; }

    receive() external payable {}

    function acceptAdmin() external {
        manager.acceptAdmin();
    }
}