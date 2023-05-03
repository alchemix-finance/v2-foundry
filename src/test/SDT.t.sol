// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {SDTController} from "../../src/SDTController.sol";

import {ISDTController} from "../../src/interfaces/ISDTController.sol";
import {IGaugeController} from "../../src/interfaces/stakedao/IGaugeController.sol";


contract STDTest is DSTestPlus {
    address constant admin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant gaugeController = 0x75f8f7fa4b6DA6De9F4fE972c811b778cefce882;
    address constant gauge = 0x7f50786A0b15723D741727882ee99a0BF34e3466;

    function testGaugeWeight() external {
        // // Set up proxy to add params
        // SDTController controller = new SDTController();
		// TransparentUpgradeableProxy proxyController = new TransparentUpgradeableProxy(address(controller), admin, abi.encode());
		// SDTController controllerImp = SDTController(address(proxyController));

        hevm.startPrank(admin);
        IGaugeController(0x75f8f7fa4b6DA6De9F4fE972c811b778cefce882).vote_for_gauge_weights(gauge, 1000);
        // ISDTController(address(controllerImp)).voteForGaugeWeights(gauge, 1000);
    }
}