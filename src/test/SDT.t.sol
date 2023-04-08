// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";

import {ISDTController} from "../../src/interfaces/ISDTController.sol";

contract STDTest is DSTestPlus {
    address constant admin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant gaugeController = 0x3216D2A52f0094AA860ca090BC5C335dE36e6273;
    address constant gauge = 0x7f50786A0b15723D741727882ee99a0BF34e3466;

    function testGaugeWeight() external {
        hevm.prank(admin);
        ISDTController(gaugeController).voteForGaugeWeight(gauge, 1000);
    }
}