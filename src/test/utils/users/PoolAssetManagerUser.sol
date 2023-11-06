// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {PoolAssetManager} from "../../../PoolAssetManager.sol";

contract PoolAssetManagerUser {
    PoolAssetManager internal manager;

    constructor(PoolAssetManager _manager) { manager = _manager; }

    function acceptAdmin() external {
        manager.acceptAdmin();
    }
}