// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {stdCheats} from "forge-std/stdlib.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {EthAssetManagerUser} from "./utils/users/EthAssetManagerUser.sol";

import {
    EthAssetManager,
    MetaPoolAsset,
    SLIPPAGE_PRECISION,
    CURVE_PRECISION,
    InitializationParams as ManagerInitializationParams
} from "../EthAssetManager.sol";

import {ITransmuterBuffer} from "../interfaces/ITransmuterBuffer.sol";
import {IERC20TokenReceiver} from "../interfaces/IERC20TokenReceiver.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IConvexBooster} from "../interfaces/external/convex/IConvexBooster.sol";
import {IConvexRewards} from "../interfaces/external/convex/IConvexRewards.sol";
import {IConvexToken} from "../interfaces/external/convex/IConvexToken.sol";
import {IEthStableMetaPool} from "../interfaces/external/curve/IEthStableMetaPool.sol";

contract EthAssetManagerTest is DSTestPlus, stdCheats {
    ITransmuterBuffer constant transmuterBuffer = ITransmuterBuffer(0xbc2FB245594a68c927C930FBE2d00680A8C90B9e);
    address constant transmuterBufferAdmin = address(0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9);
    IERC20 constant crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IEthStableMetaPool constant metaPool = IEthStableMetaPool(0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e);
    IConvexToken constant cvx = IConvexToken(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IConvexBooster constant convexBooster = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IConvexRewards constant convexRewards = IConvexRewards(0x48Bc302d8295FeA1f8c3e7F57D4dDC9981FEE410);
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    EthAssetManager manager;
    IERC20 alETH;

    function setUp() external {
        manager = new EthAssetManager(ManagerInitializationParams({
            admin:             address(this),
            operator:          address(this),
            rewardReceiver:    address(0xbeef),
            transmuterBuffer:  address(transmuterBuffer),
            weth:              weth,
            curveToken:        crv,
            metaPool:          metaPool,
            metaPoolSlippage:  SLIPPAGE_PRECISION - 30, // 30 bps, 0.3%
            convexToken:       cvx,
            convexBooster:     convexBooster,
            convexRewards:     convexRewards,
            convexPoolId:      49
        }));

        alETH = manager.getTokenForMetaPoolAsset(MetaPoolAsset.ALETH);
    }

    receive() external payable {}

    function testSetPendingAdmin() external {
        manager.setPendingAdmin(address(0xdead));
        assertEq(manager.pendingAdmin(), address(0xdead));
    }

    function testFailSetPendingAdminSenderNotAdmin() external {
        hevm.prank(address(0xdead));
        manager.setPendingAdmin(address(0xbeef));
    }

    function testAcceptAdmin() external {
        EthAssetManagerUser pendingAdmin = new EthAssetManagerUser(manager);

        manager.setPendingAdmin(address(pendingAdmin));
        pendingAdmin.acceptAdmin();

        assertEq(manager.pendingAdmin(), address(0));
        assertEq(manager.admin(), address(pendingAdmin));
    }

    function testFailAcceptAdminNotPendingAdmin() external {
        EthAssetManagerUser pendingAdmin = new EthAssetManagerUser(manager);

        manager.setPendingAdmin(address(pendingAdmin));

        hevm.prank(address(0xdead));
        manager.acceptAdmin();
    }

    function testFailAcceptAdminPendingAdminUnset() external {
        manager.acceptAdmin();
    }

    function testSetRewardReceiver() external {
        manager.setRewardReceiver(address(0xdead));
        assertEq(manager.rewardReceiver(), address(0xdead));
    }

    function testFailSetRewardReceiverSenderNotAdmin() external {
        hevm.prank(address(0xdead));
        manager.setRewardReceiver(address(0xbeef));
    }

    function testSetTransmuterBuffer() external {
        manager.setTransmuterBuffer(address(0xdead));
        assertEq(manager.transmuterBuffer(), address(0xdead));
    }

    function testFailSetTransmuterBufferSenderNotAdmin() external {
        hevm.prank(address(0xdead));
        manager.setTransmuterBuffer(address(0xbeef));
    }

    function testSetMetaPoolSlippage() external {
        manager.setMetaPoolSlippage(1e4);
        assertEq(manager.metaPoolSlippage(), 1e4);
    }

    function testSetMetaPoolSlippage(uint256 value) external {
        value = bound(value, 0, SLIPPAGE_PRECISION);
        manager.setMetaPoolSlippage(value);

        assertEq(manager.metaPoolSlippage(), value);
    }

    function testFailSetMetaPoolSlippageSenderNotAdmin() external {
        hevm.prank(address(0xdead));
        manager.setMetaPoolSlippage(1e4);
    }

    function testMintMetaPoolTokensMultipleAssets() external {
        tip(address(weth), address(manager), 1e18);
        tip(address(alETH), address(manager), 1e18);

        uint256[2] memory amounts;
        amounts[uint256(MetaPoolAsset.ETH)]   = 1e18;
        amounts[uint256(MetaPoolAsset.ALETH)] = 1e18;

        uint256 expectedOutput = 2e18 * CURVE_PRECISION / metaPool.get_virtual_price();
        uint256 minted         = manager.mintMetaPoolTokens(amounts);

        assertEq(address(manager).balance, 0);
        assertEq(weth.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.metaPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintMetaPoolTokensMultipleAssetsETH() external {
        hevm.deal(address(manager), 1e18);

        uint256[2] memory amounts;
        amounts[uint256(MetaPoolAsset.ETH)] = 1e18;

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / metaPool.get_virtual_price();
        uint256 minted         = manager.mintMetaPoolTokens(amounts);

        assertEq(address(manager).balance, 0);
        assertEq(metaPool.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.metaPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintMetaPoolTokensMultipleAssetsWETH() external {
        tip(address(weth), address(manager), 1e18);

        uint256[2] memory amounts;
        amounts[uint256(MetaPoolAsset.ETH)] = 1e18;

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / metaPool.get_virtual_price();
        uint256 minted         = manager.mintMetaPoolTokens(amounts);

        assertEq(address(manager).balance, 0);
        assertEq(metaPool.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.metaPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintMetaPoolTokensMultipleAssetsSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");

        uint256[2] memory amounts;
        manager.mintMetaPoolTokens(amounts);
    }

    function testMintMetaPoolTokensWETH() external {
        tip(address(weth), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / metaPool.get_virtual_price();
        uint256 minted         = manager.mintMetaPoolTokens(MetaPoolAsset.ETH, 1e18);

        assertEq(weth.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.metaPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintMetaPoolTokensETH() external {
        hevm.deal(address(manager), 1e18);

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / metaPool.get_virtual_price();
        uint256 minted         = manager.mintMetaPoolTokens(MetaPoolAsset.ETH, 1e18);

        assertEq(address(manager).balance, 0);
        assertEq(metaPool.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.metaPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintMetaPoolTokensSingleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.mintMetaPoolTokens(MetaPoolAsset.ETH, 0);
    }

    function testBurnMetaPoolTokens() external {
        tip(address(metaPool), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * metaPool.get_virtual_price() / CURVE_PRECISION;
        uint256 withdrawn      = manager.burnMetaPoolTokens(MetaPoolAsset.ALETH, 1e18);

        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(alETH.balanceOf(address(manager)), withdrawn);
        assertGt(withdrawn, expectedOutput * manager.metaPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testBurnMetaPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.burnMetaPoolTokens(MetaPoolAsset.ETH, 0);
    }

    function testDepositMetaPoolTokens() external {
        tip(address(metaPool), address(manager), 1e18);

        assertTrue(manager.depositMetaPoolTokens(1e18));
        assertEq(convexRewards.balanceOf(address(manager)), 1e18);
    }

    function testDepositMetaPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.depositMetaPoolTokens(0);
    }

    function testWithdrawMetaPoolTokens() external {
        tip(address(metaPool), address(manager), 1e18);

        manager.depositMetaPoolTokens(1e18);

        assertTrue(manager.withdrawMetaPoolTokens(1e18));

        assertEq(convexRewards.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), 1e18);
    }

    function testWithdrawMetaPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.withdrawMetaPoolTokens(0);
    }

    function testClaimRewards() external {
        tip(address(metaPool), address(manager), 1e18);

        manager.depositMetaPoolTokens(1e18);

        hevm.warp(block.timestamp + 86400);

        (uint256 earnedCurve, uint256 earnedConvex) = manager.claimableRewards();

        assertTrue(manager.claimRewards());
        assertEq(crv.balanceOf(manager.rewardReceiver()), earnedCurve);
        assertEq(cvx.balanceOf(manager.rewardReceiver()), earnedConvex);
    }

    function testClaimRewardsSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.claimRewards();
    }

    function testFlushMultipleAssets() external {
        hevm.deal(address(manager), 1e18);

        tip(address(weth), address(manager), 1e18);
        tip(address(alETH), address(manager), 1e18);

        uint256[2] memory amounts;
        amounts[uint256(MetaPoolAsset.ETH)]   = 2e18;
        amounts[uint256(MetaPoolAsset.ALETH)] = 1e18;

        uint256 minted = manager.flush(amounts);

        assertEq(address(manager).balance, 0);
        assertEq(weth.balanceOf(address(manager)), 0);
        assertEq(alETH.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(convexRewards.balanceOf(address(manager)), minted);
    }

    function testFlushMultipleAssetsSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.flush(MetaPoolAsset.ETH, 1e18);
    }

    function testFlushETH() external {
        hevm.deal(address(manager), 1e18);

        manager.setMetaPoolSlippage(0);

        uint256 minted = manager.flush(MetaPoolAsset.ETH, 1e18);

        assertEq(address(manager).balance, 0);
        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(convexRewards.balanceOf(address(manager)), minted);
    }

    function testFlushWETH() external {
        tip(address(weth), address(manager), 1e18);

        manager.setMetaPoolSlippage(0);

        uint256 minted = manager.flush(MetaPoolAsset.ETH, 1e18);

        assertEq(weth.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(convexRewards.balanceOf(address(manager)), minted);
    }

    function testFlushSingleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.flush(MetaPoolAsset.ETH, 1e18);
    }

    function testRecall() external {
        tip(address(metaPool), address(manager), 1e18);

        manager.depositMetaPoolTokens(1e18);

        manager.setMetaPoolSlippage(0);

        uint256 withdrawn = manager.recall(1e18);

        assertEq(address(manager).balance, withdrawn);
        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(convexRewards.balanceOf(address(manager)), 0);
    }

    function testRecallSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.recall(1e18);
    }

    function testReclaimETH() external {
        hevm.deal(address(manager), 1e18);
        tip(address(weth), address(manager), 1e18);

        hevm.prank(transmuterBufferAdmin);
        transmuterBuffer.setSource(address(manager), true);

        hevm.expectCall(
            manager.transmuterBuffer(),
            abi.encodeWithSelector(
                IERC20TokenReceiver.onERC20Received.selector,
                address(weth),
                2e18
            )
        );

        manager.reclaimEth(2e18);
    }

    function testFailReclaimETHSenderNotAdmin() external {
        tip(address(weth), address(manager), 1e18);

        hevm.prank(address(0xdead));
        manager.reclaimEth(1e18);
    }

    function testSweepToken() external {
        tip(address(weth), address(manager), 1e18);

        manager.sweepToken(address(weth), 1e18);

        assertEq(weth.balanceOf(address(manager)), 0e18);
        assertEq(weth.balanceOf(manager.admin()), 1e18);
    }

    function testFailSweepTokenSenderNotAdmin() external {
        tip(address(weth), address(manager), 1e18);

        hevm.prank(address(0xdead));
        manager.sweepToken(address(weth), 1e18);
    }

    function testSweepETH() external {
        EthAssetManagerUser admin = new EthAssetManagerUser(manager);

        manager.setPendingAdmin(address(admin));
        admin.acceptAdmin();

        hevm.deal(address(manager), 1e18);

        hevm.prank(address(admin));
        manager.sweepEth(1e18);

        assertEq(address(manager).balance, 0);
        assertEq(address(admin).balance, 1e18);
    }

    function testFailSweepSenderNotAdmin() external {
        hevm.deal(address(manager), 1e18);

        hevm.prank(address(0xdead));
        manager.sweepEth(1e18);
    }
}