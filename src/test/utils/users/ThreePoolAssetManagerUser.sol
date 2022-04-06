// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {ThreePoolAssetManager} from "../../../ThreePoolAssetManager.sol";

contract ThreePoolAssetManagerUser {
    ThreePoolAssetManager internal manager;

    constructor(ThreePoolAssetManager _manager) { manager = _manager; }

    function acceptAdmin() external {
        manager.acceptAdmin();
    }
}