// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";

import {
    AAVETokenAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/aave/AAVETokenAdapter.sol";

import {StaticAToken} from "../external/aave/StaticAToken.sol";
import {ILendingPool} from "../interfaces/external/aave/ILendingPool.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {Whitelist} from "../utils/Whitelist.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";
import {IATokenGateway} from "../interfaces/IATokenGateway.sol";
import {ATokenGateway} from "../adapters/aave/ATokenGateway.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract ATokenGatewayTest is DSTestPlus, stdCheats {
    uint256 constant BPS = 10000;
    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // ETH mainnet DAI
    address constant aToken = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
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
        staticAToken = new StaticAToken(
            lendingPool,
            aToken,
            wrappedTokenName,
            wrappedTokenSymbol
        );
        adapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:       alchemist,
            token:           address(staticAToken),
            underlyingToken: address(dai)
        }));
        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });
        
        whitelist = new Whitelist();
        gateway = new ATokenGateway(address(whitelist));
        whitelist.add(address(this));

        hevm.startPrank(alchemistAdmin);
        IAlchemistV2(alchemist).addYieldToken(address(staticAToken), ytc);
        IAlchemistV2(alchemist).setYieldTokenEnabled(address(staticAToken), true);
        IWhitelist(alchemistWhitelist).add(address(gateway));
        IWhitelist(alchemistWhitelist).add(address(this));
        hevm.stopPrank();

    }

    function testDepositWithdraw() external {
        uint256 amount = 1000 ether;
        tip(dai, address(this), amount);
        IERC20(dai).approve(address(lendingPool), amount);
        lendingPool.deposit(dai, amount, address(this), 0);
        uint256 startBal = IERC20(aToken).balanceOf(address(this));
        IERC20(aToken).approve(address(gateway), startBal);
        uint256 price = IAlchemistV2(alchemist).getUnderlyingTokensPerShare(address(staticAToken));
        uint256 sharesIssued = gateway.deposit(alchemist, aToken, address(staticAToken), startBal, address(this));
        uint256 expectedValue = sharesIssued * price / 1e18;
        assertApproxEq(amount, expectedValue, 10000);

        uint256 midBal = IERC20(aToken).balanceOf(address(this));
        assertEq(midBal, 0);

        IAlchemistV2(alchemist).approveWithdraw(address(gateway), address(staticAToken), sharesIssued);
        gateway.withdraw(alchemist, aToken, address(staticAToken), sharesIssued, address(this));
        (uint256 endShares, ) = IAlchemistV2(alchemist).positions(address(this), address(staticAToken));
        assertEq(endShares, 0);

        uint256 endBal = IERC20(aToken).balanceOf(address(this));
        assertEq(endBal, amount);
    }
}