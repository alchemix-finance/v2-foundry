// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {YearnTokenAdapterOptimism} from "../adapters/yearn/YearnTokenAdapterOptimism.sol";

import {YearnStakingToken} from "../external/yearn/YearnStakingToken.sol";
import {ILendingPool} from "../interfaces/external/aave/ILendingPool.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {Whitelist} from "../utils/Whitelist.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";
import {ITokenGateway} from "../interfaces/ITokenGateway.sol";
import {YTokenGateway} from "../adapters/yearn/YTokenGateway.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract YTokenGatewayTest is DSTestPlus {
    uint256 constant BPS = 10000;
    address constant dai = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // ETH mainnet DAI
    address constant yToken = 0x65343F414FFD6c97b0f6add33d16F6845Ac22BAc;
    YearnStakingToken stakingToken;
    YearnTokenAdapterOptimism adapter;
    ITokenGateway gateway;
    IWhitelist whitelist;
    address alchemist = 0x10294d57A419C8eb78C648372c5bAA27fD1484af;
    address alchemistAdmin = 0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a;
    address alchemistWhitelist = 0xc3365984110dB9b84c7e3Fc1cffb370C6Df6380F;

    function setUp() external {
        stakingToken = new YearnStakingToken(
            0xf8126EF025651E1B313a6893Fcf4034F4F4bD2aA,
            0x65343F414FFD6c97b0f6add33d16F6845Ac22BAc,
            dai,
            0x4200000000000000000000000000000000000042,
            0x7D2382b1f8Af621229d33464340541Db362B4907,
            address(this),
            "yearnStakingDai",
            "ySDai"
        );

        adapter = new YearnTokenAdapterOptimism(address(stakingToken), dai);

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });
        
        whitelist = new Whitelist();
        gateway = new YTokenGateway(address(whitelist), alchemist);
        whitelist.add(address(this));

        hevm.startPrank(alchemistAdmin);
        IAlchemistV2(alchemist).addYieldToken(address(stakingToken), ytc);
        IAlchemistV2(alchemist).setYieldTokenEnabled(address(stakingToken), true);
        IWhitelist(alchemistWhitelist).add(address(gateway));
        IWhitelist(alchemistWhitelist).add(address(this));
        hevm.stopPrank();

    }

    function testDepositWithdraw() external {
        uint256 amount = 1e18;
        deal(yToken, address(this), amount);
        IERC20(yToken).approve(address(gateway), 1e18);
        uint256 price = IAlchemistV2(alchemist).getUnderlyingTokensPerShare(address(stakingToken));
        uint256 sharesIssued = gateway.deposit(address(stakingToken), 1e18, address(this));
        uint256 expectedValue = sharesIssued * price / 1e18;
        assertApproxEq(price, expectedValue, 10000);

        uint256 midBal = IERC20(yToken).balanceOf(address(this));
        assertEq(midBal, 0);

        IAlchemistV2(alchemist).approveWithdraw(address(gateway), address(stakingToken), sharesIssued);
        uint256 amountWithdrawn = gateway.withdraw(address(stakingToken), sharesIssued, address(this));
        (uint256 endShares, ) = IAlchemistV2(alchemist).positions(address(this), address(stakingToken));
        assertEq(endShares, 0);

        uint256 endBal = IERC20(yToken).balanceOf(address(this));
        assertEq(endBal, amount);
        assertEq(amountWithdrawn, endBal);
    }
}