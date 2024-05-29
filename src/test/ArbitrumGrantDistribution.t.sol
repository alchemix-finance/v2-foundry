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
    address constant alchemist = 0xb46eE2E4165F629b4aBCE04B7Eb4237f951AC66F;
    address constant whitelist = 0xda94B6536E9958d63229Dc9bE4fa654Ad52921dB;

    RewardRouter router = new RewardRouter();
    ArbitrumRewardCollector collector = new ArbitrumRewardCollector(InitializationParams(alchemist, 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A, address(router), 0x912CE59144191C1204E64559FE8253a0e49E6548, 0x5C23A419436F6D65c506Bbc329A783ADB3335e3C));

    function setUp() external {
        deal(0x912CE59144191C1204E64559FE8253a0e49E6548, address(router), 10e18);
        router.addVault(0x248a431116c6f6FCD5Fe1097d16d0597E24100f5, address(collector), 10e18, 604800);
        router.setHarvester(0x52E4C31933B466CD8A7cb0aAb819abAF7BE7Fc0e);

        collector.setRewardRouter(address(router));

        vm.prank(admin);
        IAlchemixHarvester(0x52E4C31933B466CD8A7cb0aAb819abAF7BE7Fc0e).setRewardRouter(address(router));

        vm.startPrank(admin);
        IWhitelist(whitelist).add(address(collector));
        vm.stopPrank();
    }

    function testDistribute() external {
        vm.warp(block.timestamp + 604800);
        vm.prank(0x10388c006a356eF584d32A314e70D0E62CfCABeE);
        IAlchemixHarvester(0x52E4C31933B466CD8A7cb0aAb819abAF7BE7Fc0e).harvest(0xb46eE2E4165F629b4aBCE04B7Eb4237f951AC66F, 0x248a431116c6f6FCD5Fe1097d16d0597E24100f5);
        assertEq(IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548).balanceOf(address(router)) , 0);
    }

    // function testDistributePartial() external {
    //     vm.warp(block.timestamp + 302400);
    //     vm.prank(0x10388c006a356eF584d32A314e70D0E62CfCABeE);
    //     IAlchemixHarvester(0x52E4C31933B466CD8A7cb0aAb819abAF7BE7Fc0e).harvest(0xb46eE2E4165F629b4aBCE04B7Eb4237f951AC66F, 0x248a431116c6f6FCD5Fe1097d16d0597E24100f5);
    //     assertEq(IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548).balanceOf(address(router)) , 500e18);
    // }
}