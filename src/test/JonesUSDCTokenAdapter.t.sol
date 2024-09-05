// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";

import {JonesUSDCAdapter} from "../adapters/jonesDao/JonesUSDCAdapter.sol";

import {IJonesWhitelist} from "../interfaces/external/jones/IJonesWhitelist.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract JonesUSDCAdapterTest is DSTestPlus {
    address constant admin = 0x886FF7a2d46dcc2276e2fD631957969441130847;
    address constant alchemistUSD = 0xb46eE2E4165F629b4aBCE04B7Eb4237f951AC66F;
    address constant alUSD = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address constant owner = 0x886FF7a2d46dcc2276e2fD631957969441130847;
    address constant whitelistUSD = 0xda94B6536E9958d63229Dc9bE4fa654Ad52921dB;
    address constant jUSDC = 0xB0BDE111812EAC913b392D80D51966eC977bE3A2;
    address constant usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant jonesWhitelist = 0xDe3476a7C0a408325385605203665A8836c2bcca;
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    JonesUSDCAdapter adapter;

    function setUp() external {
        adapter = new JonesUSDCAdapter(0x9c895CcDd1da452eb390803d48155e38f9fC2e4d, usdc, jUSDC);

        hevm.startPrank(owner);
        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });

        IAlchemistV2(alchemistUSD).addYieldToken(jUSDC, ytc);
        IAlchemistV2(alchemistUSD).setYieldTokenEnabled(jUSDC, true);
        IWhitelist(whitelistUSD).add(address(adapter));
        IWhitelist(whitelistUSD).add(address(this));
        IAlchemistV2(alchemistUSD).setMaximumExpectedValue(address(jUSDC), 10000000000000 ether);
        IAlchemistV2(alchemistUSD).setTokenAdapter(address(jUSDC), address(adapter));
        hevm.stopPrank();

        hevm.startPrank(0xc8ce0aC725f914dBf1D743D51B6e222b79F479f1);
        IJonesWhitelist(jonesWhitelist).addToWhitelist(address(adapter));
        IJonesWhitelist(jonesWhitelist).createRole(bytes32("ALCHEMIX"), IJonesWhitelist.RoleInfo(true, 0));
        IJonesWhitelist(jonesWhitelist).addToRole(bytes32("ALCHEMIX"), address(adapter));
        hevm.stopPrank();
    }

    function testRoundTripUnderlying() external {
        deal(address(usdc), address(this), 10e6);

        // Deposit into position
        SafeERC20.safeApprove(address(usdc), alchemistUSD, 10e6);
        uint256 shares = IAlchemistV2(alchemistUSD).depositUnderlying(address(jUSDC), 10e6, address(this), 0);

        // Withdraw and unwrap
        uint256 unwrapped = IAlchemistV2(alchemistUSD).withdrawUnderlying(address(jUSDC), shares, address(this), 0);

        assertApproxEq(10e6, unwrapped, 10e6 - (10e6 * 9900 / 10_000));
    }
}