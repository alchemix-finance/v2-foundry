// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

import {IProxyAdmin} from "src/interfaces/external/IProxyAdmin.sol";
import {CrossChainCanonicalAlchemicTokenV2} from "src/CrossChainCanonicalAlchemicTokenV2.sol";

contract XTokensTest is DSTestPlus {

    function setUp() external {
        // CrossChainCanonicalAlchemicTokenV2 xToken = new CrossChainCanonicalAlchemicTokenV2();
        // vm.prank(0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a);
        // IProxyAdmin(0xd4bd68Da9bF9112CF2137D500c37bd9B842eAe85).upgrade(0x3E29D3A9316dAB217754d13b28646B76607c5f04, address(xToken));
    }

    function testPoop() external {
        CrossChainCanonicalAlchemicTokenV2 xToken = new CrossChainCanonicalAlchemicTokenV2();
        vm.prank(0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a);
        IProxyAdmin(0xd4bd68Da9bF9112CF2137D500c37bd9B842eAe85).upgrade(0x3E29D3A9316dAB217754d13b28646B76607c5f04, address(xToken));
    }
}