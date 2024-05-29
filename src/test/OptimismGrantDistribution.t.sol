// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IRewardRouter} from "../interfaces/IRewardRouter.sol";
import {IAlchemixHarvester} from "../interfaces/keepers/IAlchemixHarvester.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {OptimismRewardCollector, InitializationParams} from "../utils/collectors/OptimismRewardCollector.sol";
import {RewardRouter} from "../utils/RewardRouter.sol";

contract OptimismGrantDistribution is DSTestPlus {
    address constant admin = 0x886FF7a2d46dcc2276e2fD631957969441130847;
    address constant alchemistETH = 0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4;
    address constant whitelist = 0xc5fE32e46fD226364BFf7A035e8Ca2aBE390a68f;
    RewardRouter router = new RewardRouter();
    OptimismRewardCollector collector = new OptimismRewardCollector(InitializationParams(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4, 0x3E29D3A9316dAB217754d13b28646B76607c5f04, 0x6e39B07db3A0C7ce434Ce10335BB8BB20B7FEb48, 0x4200000000000000000000000000000000000042, 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858));

    function setUp() external {
        deal(0x4200000000000000000000000000000000000042, address(router), 1000e18);
        router.addVault(0xE62DDa84e579e6A37296bCFC74c97349D2C59ce3, address(collector), 1000e18, 604800);
        router.setHarvester(0x7066FAb261a48693Cd55de4d1ad0925B843a5005);

        collector.setRewardRouter(address(router));

        vm.prank(admin);
        IAlchemixHarvester(0x7066FAb261a48693Cd55de4d1ad0925B843a5005).setRewardRouter(address(router));

        vm.startPrank(0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a);
        IWhitelist(whitelist).add(address(collector));
        vm.stopPrank();
    }

    function testDistribute() external {
        vm.warp(block.timestamp + 604800);
        vm.prank(0x10388c006a356eF584d32A314e70D0E62CfCABeE);
        IAlchemixHarvester(0x7066FAb261a48693Cd55de4d1ad0925B843a5005).harvest(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4, 0xE62DDa84e579e6A37296bCFC74c97349D2C59ce3);
        assertEq(IERC20(0x4200000000000000000000000000000000000042).balanceOf(address(router)) , 0);
    }

        function testDistributePartial() external {
        vm.warp(block.timestamp + 302400);
        vm.prank(0x10388c006a356eF584d32A314e70D0E62CfCABeE);
        IAlchemixHarvester(0x7066FAb261a48693Cd55de4d1ad0925B843a5005).harvest(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4, 0xE62DDa84e579e6A37296bCFC74c97349D2C59ce3);
        assertEq(IERC20(0x4200000000000000000000000000000000000042).balanceOf(address(router)) , 500e18);
    }
}