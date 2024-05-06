// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

import {IProxyAdmin} from "src/interfaces/external/IProxyAdmin.sol";
import {IWhitelist} from "src/interfaces/IWhitelist.sol";
import {CrossChainCanonicalAlchemicTokenV2} from "src/CrossChainCanonicalAlchemicTokenV2.sol";
import {AlchemistV2} from "src/AlchemistV2.sol";

import "../interfaces/alchemist/IAlchemistV2Actions.sol";
import "../interfaces/alchemist/IAlchemistV2State.sol";

contract XTokensTest is DSTestPlus {

    function setUp() external {
        CrossChainCanonicalAlchemicTokenV2 xToken = new CrossChainCanonicalAlchemicTokenV2();
        AlchemistV2 newAlch = new AlchemistV2();

        vm.startPrank(0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a);
        IProxyAdmin(0xa44f69aeAC480E23C0ABFA9A55D99c9F098bEac6).upgrade(0x3E29D3A9316dAB217754d13b28646B76607c5f04, address(xToken));
        IProxyAdmin(0xd4bd68Da9bF9112CF2137D500c37bd9B842eAe85).upgrade(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4, address(newAlch));
        IWhitelist(0xc5fE32e46fD226364BFf7A035e8Ca2aBE390a68f).add(address(0xbeef));
        vm.stopPrank();
    }

    function testPoop() external {
        vm.startPrank(address(0xbeef));
        deal(0x4200000000000000000000000000000000000006, address(0xbeef), 100e18);
        SafeERC20.safeApprove(0x4200000000000000000000000000000000000006, 0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4, 100e18);
        IAlchemistV2Actions(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4).depositUnderlying(0xE62DDa84e579e6A37296bCFC74c97349D2C59ce3, 100e18, address(0xbeef), 0);

        IAlchemistV2Actions(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4).mint(40e18, address(0xbeef));

        SafeERC20.safeApprove(0x3E29D3A9316dAB217754d13b28646B76607c5f04, 0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4, 40e18);
        IAlchemistV2Actions(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4).burn(30e18, address(0xbeef));

        (int256 debt, ) = IAlchemistV2State(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4).accounts(address(0xbeef));
        console.logInt(debt);
    }
}