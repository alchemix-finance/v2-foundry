// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    apxETHAdapter
} from "../adapters/dinero/apxETHAdapter.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IPirexContract} from "../interfaces/external/pirex/IPirexContract.sol";
import {IapxEthToken} from "../interfaces/external/pirex/IapxEthToken.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

// Define the Balancer IVault interface
interface IVault {
    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    function swap(
        SingleSwap calldata singleSwap,
        FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256 amountCalculated);
}

// Mock Balancer Vault for testing
contract MockBalancerVault is IVault {
    IERC20 public pxEthToken;
    IWETH9 public weth;

    constructor(address _pxEthToken, address _weth) {
        pxEthToken = IERC20(_pxEthToken);
        weth = IWETH9(_weth);
    }

    function swap(
        SingleSwap calldata singleSwap,
        FundManagement calldata funds,
        uint256,
        uint256
    ) external payable override returns (uint256) {
        // Simulate a 1:1 swap
        require(singleSwap.assetIn == address(pxEthToken), "Invalid assetIn");
        require(singleSwap.assetOut == address(weth), "Invalid assetOut");

        // Transfer pxETH from sender to vault
        require(
            pxEthToken.transferFrom(funds.sender, address(this), singleSwap.amount),
            "pxETH transfer failed"
        );

        // For testing, assume 1 pxETH = 1 WETH
        uint256 amountOut = singleSwap.amount;

        // Mint WETH to recipient (assuming the vault has enough WETH or we're simulating)
        weth.deposit{value: amountOut}();
        weth.transfer(funds.recipient, amountOut);

        return amountOut;
    }

    receive() external payable {}
}

contract APXETHAdapterTest is DSTestPlus {
    // Addresses (Replace with actual addresses or mock addresses for testing)
    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    IAlchemistV2 constant alchemist = IAlchemistV2(0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c);
    address constant alETH = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant whitelistETH = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;

    IWETH9 weth = IWETH9(wETH);
    IERC4626 apxETH = IERC4626(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6);
    IERC20 pxETH = IERC20(0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6);
    IPirexContract apxETHDepositContract = IPirexContract(0xD664b74274DfEB538d9baC494F3a4760828B02b0);
    IVault balancerVault = IVault(0x88794C65550DeB6b4087B7552eCf295113794410);
    bytes32 balancerPoolId = 0x88794c65550deb6b4087b7552ecf295113794410000000000000000000000648;

    apxETHAdapter adapter;

    function setUp() external {
        // Fork mainnet at a specific block

        // Deal some ETH to admin to ensure they can perform transactions
        hevm.deal(admin, 100 ether);

        // Label addresses for better trace output
        hevm.label(admin, "admin");
        hevm.label(address(alchemist), "alchemist");
        hevm.label(address(apxETH), "apxETH");

        // Initialize the adapter first
        adapter = new apxETHAdapter(
            address(alchemist),
            address(apxETH),
            address(weth),
            address(balancerVault),
            balancerPoolId,
            address(pxETH),
            address(apxETHDepositContract)
        );

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });

        // Impersonate the alchemist owner
        hevm.startPrank(owner);

        // Add to whitelist
        IWhitelist(whitelistETH).add(address(adapter));
        IWhitelist(whitelistETH).add(address(this));

        // Register the token and adapter
        IAlchemistV2(alchemist).addYieldToken(address(apxETH), ytc);
        IAlchemistV2(alchemist).setYieldTokenEnabled(address(apxETH), true);
        hevm.stopPrank();



    }

    function testPrice() external {
        assertEq(adapter.price(), IERC4626(apxETH).convertToAssets(1e18));
    }

    // function testWrap() external {
    //     uint256 amountToWrap = 1e18;

    //     // Step 1: Setup initial WETH and approve Alchemist
    //     deal(address(weth), address(this), amountToWrap);
    //     SafeERC20.safeApprove(address(weth), address(alchemist), amountToWrap);

    //     // Step 2: Deposit WETH into Alchemist
    //     IAlchemistV2(alchemist).depositUnderlying(
    //         address(apxETH),
    //         amountToWrap,
    //         address(this),
    //         0  // minimum amount to mint
    //     );

    //     // Step 3: Try the wrap operation
    //     hevm.startPrank(address(alchemist));

    //     try adapter.wrap(amountToWrap, address(this)) returns (uint256 mintedShares) {
    //         assertTrue(mintedShares > 0, "Wrap succeeded but no shares minted");
    //     } catch Error(string memory reason) {
    //         fail(string.concat("Wrap failed with reason: ", reason));
    //     } catch (bytes memory) {
    //         // Get the last revert data
    //         hevm.expectRevert();
    //         adapter.wrap(amountToWrap, address(this));
    //         fail("Wrap failed with low level error - see revert data above");
    //     }

    //     hevm.stopPrank();
    // }

//   function testRoundTrip() external {
//         deal(address(wETH), address(this), 1e18);
// 		uint256 startingBalance = IERC20(apxETH).balanceOf(address(alchemist));

//         SafeERC20.safeApprove(address(wETH), address(alchemist), 1e18);
//         uint256 wrapped = IAlchemistV2(alchemist).depositUnderlying(address(apxETH), 1e18, address(this), 0);

//         uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(apxETH));
//         assertGt(underlyingValue, 1e18 * (99/100) /* 1% slippage */);

//         uint256 unwrapped = IAlchemistV2(alchemist).withdrawUnderlying(address(apxETH), wrapped, address(this), 0);

//         assertGt(unwrapped, 1e18 * (99/100) /* 1% slippage */);
//         assertEq(IERC4626(apxETH).balanceOf(address(this)), 0);
//         assertApproxEq(IERC4626(apxETH).balanceOf(address(adapter)), 0, 10);
//     }
    // function testUnwrap() external {
    //     uint256 amountToUnwrap = 1e18;

    //     deal(address(apxETH), address(this), amountToUnwrap);
    //     SafeERC20.safeApprove(address(apxETH), address(adapter), amountToUnwrap);

    //     deal(address(weth), address(balancerVault), amountToUnwrap);

    //     hevm.prank(address(alchemist));
    //     uint256 receivedWeth = adapter.unwrap(amountToUnwrap, address(this));

    //     uint256 wethBalance = weth.balanceOf(address(this));
    //     assertEq(wethBalance, receivedWeth);
    //     assertEq(wethBalance, amountToUnwrap);
    // }

    // function testDepositAndWithdraw() external {
    //     uint256 depositAmount = 1e18;
    //     deal(address(weth), address(this), depositAmount);
    //     SafeERC20.safeApprove(address(weth), address(alchemist), depositAmount);

    //     // Store and use the shares
    //     uint256 shares = IAlchemistV2(alchemist).deposit(address(apxETH), depositAmount, address(this));
    //     assertGt(shares, 0); // Verify shares were received

    //     uint256 unwrappedAmount = IAlchemistV2(alchemist).withdrawUnderlying(address(apxETH), shares, address(this), 0);

    //     uint256 wethBalance = weth.balanceOf(address(this));
    //     assertEq(wethBalance, unwrappedAmount);
    // }

    // function testHarvest() external {
    //     uint256 depositAmount = 1e18;
    //     deal(address(weth), address(this), depositAmount);
    //     SafeERC20.safeApprove(address(weth), address(alchemist), depositAmount);

    //     uint256 shares = IAlchemistV2(alchemist).deposit(address(apxETH), depositAmount, address(this));

    //     hevm.warp(block.timestamp + 1 weeks);

    //     hevm.prank(owner);
    //     IAlchemistV2(alchemist).harvest(address(apxETH), 0);

    //     (int256 debtBefore, ) = IAlchemistV2(alchemist).accounts(address(this));

    //     hevm.warp(block.timestamp + 1 weeks);

    //     hevm.prank(owner);
    //     IAlchemistV2(alchemist).harvest(address(apxETH), 0);

    //     (int256 debtAfter, ) = IAlchemistV2(alchemist).accounts(address(this));

    //     assertGt(debtBefore, debtAfter);
    // }

    // function testLiquidate() external {
    //     uint256 depositAmount = 10e18;
    //     deal(address(weth), address(this), depositAmount);
    //     SafeERC20.safeApprove(address(weth), address(alchemist), depositAmount);

    //     uint256 shares = IAlchemistV2(alchemist).deposit(address(apxETH), depositAmount, address(this));

    //     uint256 pps = IAlchemistV2(alchemist).getUnderlyingTokensPerShare(address(apxETH));
    //     uint256 borrowAmount = (shares * pps) / 1e18 / 2;
    //     IAlchemistV2(alchemist).mint(borrowAmount, address(this));

    //     hevm.prank(owner);

    //     uint256 collateralToLiquidate = shares / 2;
    //     uint256 minDebtRepayment = borrowAmount / 2;
    //     uint256 sharesLiquidated = IAlchemistV2(alchemist).liquidate(address(apxETH), collateralToLiquidate, minDebtRepayment);

    //     (int256 debtAfter,) = IAlchemistV2(alchemist).accounts(address(this));
    //     uint256 debtAfterUint = uint256(debtAfter);
    //     assertEq(
    //         debtAfterUint,
    //         uint256(borrowAmount * 2 - minDebtRepayment)
    //     );

    //     (uint256 sharesLeft, ) = IAlchemistV2(alchemist).positions(address(this), address(apxETH));
    //     assertEq(sharesLeft, shares - sharesLiquidated);
    // }
}
