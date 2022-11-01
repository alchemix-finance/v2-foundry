// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    AAVETokenAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/aave/AAVETokenAdapter.sol";

import {StaticAToken} from "../external/aave/StaticAToken.sol";
import {ILendingPool} from "../interfaces/external/aave/ILendingPool.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IAlchemistV2State} from "../interfaces/alchemist/IAlchemistV2State.sol";
import {Whitelist} from "../utils/Whitelist.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";
import {IATokenGateway} from "../interfaces/IATokenGateway.sol";
import {ATokenGateway} from "../adapters/aave/ATokenGateway.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract AlchemistV2Test is DSTestPlus {
    uint256 constant BPS = 10000;
    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // ETH mainnet DAI
    address constant ydai = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;
    ILendingPool lendingPool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    string wrappedTokenName = "staticAaveDai";
    string wrappedTokenSymbol = "saDAI";
    StaticAToken staticAToken;
    AAVETokenAdapter adapter;
    IATokenGateway gateway;
    IWhitelist whitelist;
    address alchemist = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address alchemistAdmin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address alchemistWhitelist = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;

    function setUp() external {
        hevm.prank(0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9);
        IAlchemistV2(alchemist).setKeeper(address(this), true);
        hevm.prank(0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9);
        IWhitelist(alchemistWhitelist).add(address(this));
    }

    function testConfigureCreditUnlockRate() external {
        IAlchemistV2(alchemist).harvest(ydai, 0);
        IAlchemistV2State.YieldTokenParams memory ytp = IAlchemistV2(alchemist).getYieldTokenParameters(ydai);
        uint256 newCreditUnlockRate = ytp.creditUnlockRate / 2;
        deal(dai, ydai, 1000e18);
        hevm.prank(0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9);
        IAlchemistV2(alchemist).configureCreditUnlockRate(ydai, 1e18 / newCreditUnlockRate);
        IAlchemistV2(alchemist).harvest(ydai, 0);
    }
}