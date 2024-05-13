// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IRewardRouter} from "../interfaces/IRewardRouter.sol";
import {IAlchemixHarvester} from "../interfaces/keepers/IAlchemixHarvester.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {ArbitrumRewardCollector, InitializationParams} from "../utils/collectors/ArbitrumRewardCollector.sol";
import {RewardRouter} from "../utils/RewardRouter.sol";

contract ArbitrumGrantDistribution is DSTestPlus {
    address constant admin = 0x886FF7a2d46dcc2276e2fD631957969441130847;
    address constant alchemistETH = 0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4;
    address constant whitelist = 0xc5fE32e46fD226364BFf7A035e8Ca2aBE390a68f;

    bytes pathUSD = "0x912CE59144191C1204E64559FE8253a0e49E65480001f4af88d065e77c8cC2239327C5EDb3A432268e58310000FA17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F0001f4CB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A";

    RewardRouter router = new RewardRouter();
    ArbitrumRewardCollector collector = new ArbitrumRewardCollector(InitializationParams(0xb46eE2E4165F629b4aBCE04B7Eb4237f951AC66F, 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A, address(router), 0x912CE59144191C1204E64559FE8253a0e49E6548, 0xAA23611badAFB62D37E7295A682D21960ac85A90, pathUSD, pathUSD));

    function setUp() external {
        deal(0x912CE59144191C1204E64559FE8253a0e49E6548, address(router), 1000e18);
        router.addVault(0xE62DDa84e579e6A37296bCFC74c97349D2C59ce3, address(collector), 1000e18, 604800);
        router.setHarvester(0x52E4C31933B466CD8A7cb0aAb819abAF7BE7Fc0e);

        collector.setRewardRouter(address(router));

        vm.prank(admin);
        IAlchemixHarvester(0x52E4C31933B466CD8A7cb0aAb819abAF7BE7Fc0e).setRewardRouter(address(router));

        vm.startPrank(0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a);
        IWhitelist(whitelist).add(address(collector));
        vm.stopPrank();
    }

    function testDistribute() external {
        vm.warp(block.timestamp + 604800);
        vm.prank(0x10388c006a356eF584d32A314e70D0E62CfCABeE);
        IAlchemixHarvester(0x52E4C31933B466CD8A7cb0aAb819abAF7BE7Fc0e).harvest(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4, 0xE62DDa84e579e6A37296bCFC74c97349D2C59ce3);
        assertEq(IERC20(0x4200000000000000000000000000000000000042).balanceOf(address(router)) , 0);
    }

        function testDistributePartial() external {
        vm.warp(block.timestamp + 302400);
        vm.prank(0x10388c006a356eF584d32A314e70D0E62CfCABeE);
        IAlchemixHarvester(0x52E4C31933B466CD8A7cb0aAb819abAF7BE7Fc0e).harvest(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4, 0xE62DDa84e579e6A37296bCFC74c97349D2C59ce3);
        assertEq(IERC20(0x4200000000000000000000000000000000000042).balanceOf(address(router)) , 500e18);
    }
}