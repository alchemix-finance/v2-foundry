// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";

import {JonesUSDCAdapter} from "../adapters/jonesDao/JonesUSDCAdapter.sol";

import {IJonesWhitelist} from "../interfaces/external/jones/IJonesWhitelist.sol";
import {IJonesDaoVaultRouter} from "../interfaces/external/jones/IJonesDaoVaultRouter.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IAlchemistV2Errors} from "../interfaces/alchemist/IAlchemistV2Errors.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

interface IOwnableLike { function owner() external view returns (address); }

contract MockJonesRouter {
    function deposit(uint256 amount, address) external pure returns (uint256) {
        return amount;
    }
    function withdrawRequest(uint256 amount, address, uint256, bytes calldata) external pure returns (bool, uint256) {
        return (true, amount);
    }
}

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
        MockJonesRouter mockRouter = new MockJonesRouter();
        adapter = new JonesUSDCAdapter(address(mockRouter), usdc, jUSDC);

        // Use on-chain admin for Alchemist on fork
        address adminOnChain = IAlchemistV2(alchemistUSD).admin();
        hevm.deal(adminOnChain, 100 ether);
        hevm.startPrank(adminOnChain);

        // Ensure underlying is registered/enabled (skip if already added)
        if (!IAlchemistV2(alchemistUSD).isSupportedUnderlyingToken(usdc)) {
            IAlchemistV2AdminActions.UnderlyingTokenConfig memory utc = IAlchemistV2AdminActions.UnderlyingTokenConfig({
                repayLimitMinimum: 0,
                repayLimitMaximum: type(uint256).max / 2,
                repayLimitBlocks: 1,
                liquidationLimitMinimum: 0,
                liquidationLimitMaximum: type(uint256).max / 2,
                liquidationLimitBlocks: 1
            });
            IAlchemistV2(alchemistUSD).addUnderlyingToken(usdc, utc);
            IAlchemistV2(alchemistUSD).setUnderlyingTokenEnabled(usdc, true);
        }

        // Add yield token only if not already present, otherwise just enable and update adapter
        if (!IAlchemistV2(alchemistUSD).isSupportedYieldToken(jUSDC)) {
            IAlchemistV2AdminActions.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
                adapter: address(adapter),
                maximumLoss: 1,
                maximumExpectedValue: 1000000 ether,
                creditUnlockBlocks: 7200
            });
            IAlchemistV2(alchemistUSD).addYieldToken(jUSDC, ytc);
        }
        // Ensure enabled and adapter set
        IAlchemistV2(alchemistUSD).setYieldTokenEnabled(jUSDC, true);
        IAlchemistV2(alchemistUSD).setMaximumExpectedValue(address(jUSDC), 10000000000000 ether);
        IAlchemistV2(alchemistUSD).setTokenAdapter(address(jUSDC), address(adapter));
        IAlchemistV2(alchemistUSD).setMaximumLoss(jUSDC, 10_000);
        hevm.stopPrank();

        // Whitelist adapter and this test contract using whitelist owner
        address whitelistOwner = IOwnableLike(whitelistUSD).owner();
        hevm.deal(whitelistOwner, 10 ether);
        hevm.startPrank(whitelistOwner);
        IWhitelist(whitelistUSD).add(address(adapter));
        IWhitelist(whitelistUSD).add(address(this));
        hevm.stopPrank();

        // Jones whitelist setup (may be unnecessary with mocks, but harmless)
        address jonesAdmin = 0xc8ce0aC725f914dBf1D743D51B6e222b79F479f1;
        hevm.deal(jonesAdmin, 10 ether);
        hevm.startPrank(jonesAdmin);
        IJonesWhitelist(jonesWhitelist).addToWhitelist(address(adapter));
        IJonesWhitelist(jonesWhitelist).createRole(bytes32("ALCHEMIX"), IJonesWhitelist.RoleInfo(true, 0));
        IJonesWhitelist(jonesWhitelist).addToRole(bytes32("ALCHEMIX"), address(adapter));
        hevm.stopPrank();

        // Ensure adapter.price() doesn't revert on fork by mocking convertToAssets (not used now, but harmless)
        hevm.mockCall(
            jUSDC,
            abi.encodeWithSelector(IERC4626.convertToAssets.selector, uint256(1e18)),
            abi.encode(uint256(1e6))
        );
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
    function testDepositThenMintReverts() external {
        uint256 depositAmount = 10e6; // 10 USDC
        deal(address(usdc), address(this), depositAmount);

        // Deposit USDC as jUSDC collateral
        SafeERC20.safeApprove(address(usdc), alchemistUSD, depositAmount);
        IAlchemistV2(alchemistUSD).depositUnderlying(address(jUSDC), depositAmount, address(this), 0);

        // With adapter.price() hardcoded to 1, collateral value is effectively ~0
        // Attempt to mint a meaningful amount (1 alUSD) and expect Undercollateralized
        hevm.expectRevert(IAlchemistV2Errors.Undercollateralized.selector);
        IAlchemistV2(alchemistUSD).mint(1e6, address(this));
    }
}