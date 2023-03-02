// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {AlchemistV2} from "../AlchemistV2.sol";
import {AlchemixTokenMath} from "../utils/AlchemixTokenMath.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract VesperAdapterV1Test is DSTestPlus {
    address constant alchemistETHAddress = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant alchemistUSDAddress = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant vaDAI = 0x0538C8bAc84E95A9dF8aC10Aad17DbE81b9E36ee;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant vaUSDC = 0xa8b607Aa09B6A2E306F93e74c282Fb13f6A80452;
    address constant vaETH = 0xd1C117319B3595fbc39b471AB1fd485629eb05F2;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function testMathVesperUSDC() external {
        AlchemixTokenMath math = new AlchemixTokenMath();

        uint256 debt = math.normalizeSharesToDebtTokens(1e18, vaUSDC, USDC, alchemistUSDAddress);

        uint256 shares = math.normalizeDebtTokensToShares(debt, vaUSDC, USDC, alchemistUSDAddress);

        assertEq(shares, 1e18);
    }

    function testMathVesperDAI() external {
        AlchemixTokenMath math = new AlchemixTokenMath();

        uint256 debt = math.normalizeSharesToDebtTokens(1e18, vaDAI, DAI, alchemistUSDAddress);

        uint256 shares = math.normalizeDebtTokensToShares(debt, vaDAI, DAI, alchemistUSDAddress);

        assertEq(shares, 1e18);
    }

    function testMathVesperETH() external {
        AlchemixTokenMath math = new AlchemixTokenMath();

        uint256 debt = math.normalizeSharesToDebtTokens(1e18, vaETH, WETH, alchemistETHAddress);

        uint256 shares = math.normalizeDebtTokensToShares(debt, vaETH, WETH, alchemistETHAddress);

        assertEq(shares, 1e18);
    }
}