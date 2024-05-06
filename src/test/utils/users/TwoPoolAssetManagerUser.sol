// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {TwoPoolAssetManager} from "../../../TwoPoolAssetManager.sol";

contract TwoPoolAssetManagerUser {
    TwoPoolAssetManager internal manager;

    constructor(TwoPoolAssetManager _manager) { manager = _manager; }

    function acceptAdmin() external {
        manager.acceptAdmin();
    }
}