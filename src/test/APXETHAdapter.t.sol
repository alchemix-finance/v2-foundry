// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";

import {
    apxETHAdapter
} from "../adapters/dinero/apxETHAdapter.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IPirexContract} from "../interfaces/external/pirex/IPirexContract.sol";
import {IapxEthToken} from "../interfaces/external/pirex/IapxEthToken.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

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
        uint256 limit,
        uint256 deadline
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

contract apxETHAdapterTest is DSTestPlus {
    // Addresses (Replace with actual addresses or mock addresses for testing)
    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant alchemistETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant alETH = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant whitelistETH = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;

    IWETH9 weth = IWETH9(wETH);
    IERC20 apxETH = IERC20(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6); // apxETH token address
    IERC20 pxETH = IERC20(0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6); // pxETH token address
    IPirexContract pirexContract = IPirexContract(0xD664b74274DfEB538d9baC494F3a4760828B02b0); // Pirex contract address
    IapxEthToken apxEthTokenContract = IapxEthToken(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6); // apxETH token contract

    IVault balancerVault;
    bytes32 balancerPoolId = 0x88794c65550deb6b4087b7552ecf295113794410000000000000000000000648;

    apxETHAdapter adapter;

    function setUp() external {
        // Deploy the mock Balancer Vault
        MockBalancerVault mockBalancerVault = new MockBalancerVault(address(pxETH), address(weth));
        balancerVault = IVault(address(mockBalancerVault));

        // Initialize the adapter with Balancer Vault and Pool ID
        adapter = new apxETHAdapter(
            alchemistETH,
            address(apxETH),
            address(pxETH),
            address(weth),
            address(pirexContract),
            address(apxEthTokenContract),
            address(balancerVault),
            balancerPoolId
        );

        // Set up the Alchemist and Whitelist configurations
        hevm.startPrank(owner);
        IWhitelist(whitelistETH).add(address(adapter));
        IWhitelist(whitelistETH).add(address(this));
        IAlchemistV2(alchemistETH).setMaximumExpectedValue(address(apxETH), 10000000000000 ether);
        IAlchemistV2(alchemistETH).setTokenAdapter(address(apxETH), address(adapter));
        hevm.stopPrank();
    }

    function testPrice() external {
        uint256 expectedPrice = adapter.price();
        assertEq(expectedPrice, 1e18); // Assuming price is 1e18 as per adapter
    }

    function testWrap() external {
        // Arrange
        uint256 amountToWrap = 1e18;
        deal(address(weth), address(this), amountToWrap);
        SafeERC20.safeApprove(address(weth), address(adapter), amountToWrap);

        // Act
        hevm.prank(alchemistETH);
        uint256 mintedShares = adapter.wrap(amountToWrap, address(this));

        // Assert
        uint256 apxEthBalance = apxETH.balanceOf(address(this));
        assertEq(apxEthBalance, mintedShares);
        // Optionally, check that the mintedShares are within expected range
    }

    function testUnwrap() external {
        // Arrange
        uint256 amountToUnwrap = 1e18;

        // Mint apxETH to this contract
        deal(address(apxETH), address(this), amountToUnwrap);
        SafeERC20.safeApprove(address(apxETH), address(adapter), amountToUnwrap);

        // Ensure the mock Balancer Vault has enough WETH for the swap
        deal(address(weth), address(balancerVault), amountToUnwrap);

        // Act
        hevm.prank(alchemistETH);
        uint256 receivedWeth = adapter.unwrap(amountToUnwrap, address(this));

        // Assert
        uint256 wethBalance = weth.balanceOf(address(this));
        assertEq(wethBalance, receivedWeth);
        assertEq(wethBalance, amountToUnwrap); // Assuming 1:1 swap rate
    }

    function testDepositAndWithdraw() external {
        // Arrange
        uint256 depositAmount = 1e18;
        deal(address(weth), address(this), depositAmount);
        SafeERC20.safeApprove(address(weth), alchemistETH, depositAmount);

        // Act
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(apxETH), depositAmount, address(this));

        // Withdraw and unwrap
        uint256 unwrappedAmount = IAlchemistV2(alchemistETH).withdrawUnderlying(address(apxETH), shares, address(this), 0);

        // Assert
        uint256 wethBalance = weth.balanceOf(address(this));
        assertEq(wethBalance, unwrappedAmount);
        // Verify that the unwrapped amount matches expectations
    }

    function testHarvest() external {
        // Arrange
        uint256 depositAmount = 1e18;
        deal(address(weth), address(this), depositAmount);
        SafeERC20.safeApprove(address(weth), alchemistETH, depositAmount);

        // Deposit into the Alchemist
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(apxETH), depositAmount, address(this));

        // Simulate time passing for yield to accrue
        hevm.warp(block.timestamp + 1 weeks);

        // Act
        // Harvest the yield
        hevm.prank(owner);
        IAlchemistV2(alchemistETH).harvest(address(apxETH), 0);

        // Assert
        // Check that yield was harvested and credited
        (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        // Simulate another week passing
        hevm.warp(block.timestamp + 1 weeks);

        // Harvest again
        hevm.prank(owner);
        IAlchemistV2(alchemistETH).harvest(address(apxETH), 0);

        (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        assertGt(debtBefore, debtAfter);
    }

    function testLiquidate() external {
        // Arrange
        uint256 depositAmount = 10e18;
        deal(address(weth), address(this), depositAmount);
        SafeERC20.safeApprove(address(weth), alchemistETH, depositAmount);

        // Deposit into the Alchemist
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(apxETH), depositAmount, address(this));

        // Borrow some alETH against the deposited collateral
        uint256 pps = IAlchemistV2(alchemistETH).getUnderlyingTokensPerShare(address(apxETH));
        uint256 borrowAmount = (shares * pps) / 1e18 / 2; // Borrow up to 50% LTV
        IAlchemistV2(alchemistETH).mint(borrowAmount, address(this));

        // Simulate undercollateralization
        hevm.prank(owner);
        IAlchemistV2(alchemistETH).setAccountDebt(address(this), int256(borrowAmount * 2));

        // Act
        // Liquidate part of the collateral to repay debt
        uint256 collateralToLiquidate = shares / 2;
        uint256 minDebtRepayment = borrowAmount / 2;
        uint256 sharesLiquidated = IAlchemistV2(alchemistETH).liquidate(address(apxETH), collateralToLiquidate, minDebtRepayment);

        // Assert
        // Check that the debt has been reduced
        (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));
        assertApproxEq(debtAfter, int256(borrowAmount * 2 - minDebtRepayment), 1);

        // Check that the shares have been reduced
        (uint256 sharesLeft, ) = IAlchemistV2(alchemistETH).positions(address(this), address(apxETH));
        assertEq(sharesLeft, shares - sharesLiquidated);
    }
}
