// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../lib/ds-test/src/test.sol";

import { Invariants } from "./utils/Invariants.sol";
import "../interfaces/alchemist/IAlchemistV2State.sol";

contract TestInvariants is Invariants {
	function setUp() public {}

	/*
	 * Test that the invariants are preserved by the deposit function
	 *
	 * Values defined as uint96 to restrict the range that the inputs can be
	 * fuzzed over: inputs close to 2^128 can cause arithmetic overflows
	 */
	function testInvariantsOnDeposit(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		// Assign yield tokens to a user
		assignToUser(userList[0], fakeUnderlyingToken, amount);
		assignYieldTokenToUser(userList[0], fakeYieldToken, amount);

		// Deposit yield tokens
		alchemist.deposit(fakeYieldToken, amount, userList[0]);

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}

	/*
	 * Test that the invariants are preserved by the depositUnderlying function
	 */
	function testInvariantsOnDepositUnderlying(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		// Assign yield tokens to a user
		assignToUser(userList[0], fakeUnderlyingToken, amount);

		// Deposit underlying tokens
		alchemist.depositUnderlying(fakeYieldToken, amount, userList[0], minimumAmountOut(amount, fakeYieldToken));

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}

	/*
	 * Test that the invariants are preserved by the withdraw function
	 */
	function testInvariantsOnWithdraw(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure first user has enough collateral to withdraw
		cheats.assume(amount <= overCollateralList[0]);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYieldToken);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlyingToken);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Withdraw yield token
		alchemist.withdraw(fakeYieldToken, sharesToWithdraw, recipient);

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}

	/*
	 * Test that the invariants are preserved by the withdrawUnderlying function
	 */
	function testInvariantsOnWithdrawUnderlying(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure first user has enough collateral to withdraw
		cheats.assume(amount <= overCollateralList[0]);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYieldToken);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlyingToken);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Withdraw underlying token
		alchemist.withdrawUnderlying(
			fakeYieldToken,
			sharesToWithdraw,
			recipient,
			minimumAmountOut(amount, fakeYieldToken)
		);

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}

	/*
	 * Test that the invariants are preserved by the withdrawFrom function
	 */
	function testInvariantsOnWithdrawFrom(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure first user has enough collateral to withdraw
		cheats.assume(amount <= overCollateralList[0]);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYieldToken);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlyingToken);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Approve a different account to withdraw
		alchemist.approveWithdraw(userList[1], fakeYieldToken, sharesToWithdraw);

		cheats.stopPrank();

		// Switch to approved account
		cheats.startPrank(userList[1], userList[1]);

		// Withdraw yield from an owner's account
		alchemist.withdrawFrom(userList[0], fakeYieldToken, sharesToWithdraw, recipient);

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}

	/*
	 * Test that the invariants are preserved by the withdrawUnderlyingFrom function
	 */
	function testInvariantsOnWithdrawUnderlyingFrom(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure first user has enough collateral to withdraw
		cheats.assume(amount <= overCollateralList[0]);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYieldToken);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlyingToken);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Approve a different account to withdraw
		alchemist.approveWithdraw(userList[1], fakeYieldToken, sharesToWithdraw);

		cheats.stopPrank();

		// Switch to approved account
		cheats.startPrank(userList[1], userList[1]);

		// Withdraw underlying token from an owner's account
		alchemist.withdrawUnderlyingFrom(
			userList[0],
			fakeYieldToken,
			sharesToWithdraw,
			recipient,
			minimumAmountOut(amount, fakeYieldToken)
		);

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}

	/*
	 * Test that the invariants are preserved by the mint function
	 */
	function testInvariantsOnMint(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure first user has enough collateral to mint
		cheats.assume(amount <= (overCollateralList[0] / 2));

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		// Mint debt from an account
		alchemist.mint(amount, userList[0]);
		minted += amount;

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}

	/*
	 * Test that the invariants are preserved by the mintFrom function
	 */
	function testInvariantsOnMintFrom(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure first user has enough collateral to mint
		cheats.assume(amount <= (overCollateralList[0] / 2));

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		// Approve a different account to mint debt
		alchemist.approveMint(userList[1], amount);

		cheats.stopPrank();

		// Switch to an account to mint from
		cheats.startPrank(userList[1], userList[1]);

		// Mint debt from an owner's account
		alchemist.mintFrom(userList[0], amount, userList[1]);
		minted += amount;

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}

	/*
	 * Test that the invariants are preserved by the repay function
	 */
	function testInvariantsOnRepay(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure account has debt to repay
		cheats.assume(debtList[0] > 0);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		uint256 repayAmount = setRepayAmount(userList[0], fakeUnderlyingToken, amount);

		alchemist.repay(fakeUnderlyingToken, repayAmount, userList[0]);

		// Maximum amount that can be repaid is the account's total debt
		sentToTransmuter += ((repayAmount > debtList[0]) ? debtList[0] : repayAmount);

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}

	/*
	 * Test that the invariants are preserved by the burn function
	 */
	function testInvariantsOnBurn(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure account has debt to burn
		cheats.assume(debtList[0] > amount);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		// Burn debt tokens
		alToken.approve(address(alchemist), amount);
		alchemist.burn(amount, userList[0]);
		burned += amount;

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}

	/*
	 * Test that the invariants are preserved by the liquidate function
	 */
	function testInvariantsOnLiquidate(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure account has debt to liquidate
		cheats.assume(debtList[0] > 0);

		// Check that invariants hold before interaction
		invariantA1Range(userList, fakeYieldToken, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYieldToken);
		invariantA3(userList, fakeYieldToken);
		invariantA7(userList, fakeYieldToken);
		invariantA8(userList, fakeYieldToken, fakeUnderlyingToken);

		cheats.startPrank(userList[0], userList[0]);

		uint256 liquidationAmount = setLiquidationAmount(fakeUnderlyingToken, amount);

		alchemist.liquidate(fakeYieldToken, liquidationAmount, minimumAmountOut(liquidationAmount, fakeYieldToken));
		sentToTransmuter += liquidationAmount;

		cheats.stopPrank();

		// Check that invariants hold after interaction
		invariantA1Range(userList, fakeYieldToken, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYieldToken);
		invariantA3(userList, fakeYieldToken);
		invariantA7(userList, fakeYieldToken);
		invariantA8(userList, fakeYieldToken, fakeUnderlyingToken);
	}

	function testInvariantsOnDonate(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure amount is a meaningful size to donate
		cheats.assume(amount > 1e18);
		cheats.assume(debtList[0] > amount);

		// Check that invariants hold before interaction
		invariantA1Range(userList, fakeYieldToken, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYieldToken);
		invariantA3(userList, fakeYieldToken);
		invariantA7(userList, fakeYieldToken);
		invariantA8(userList, fakeYieldToken, fakeUnderlyingToken);

		cheats.startPrank(userList[0], userList[0]);

		alToken.approve(address(alchemist), amount);
		alchemist.donate(fakeYieldToken, amount);
		burned += amount;

		cheats.stopPrank();

		// Check that invariants hold after interaction
		invariantA1Range(userList, fakeYieldToken, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYieldToken);
		invariantA3(userList, fakeYieldToken);
		invariantA7(userList, fakeYieldToken);
		invariantA8(userList, fakeYieldToken, fakeUnderlyingToken);
	}

	function testInvariantsOnHarvest(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Ensure amount is a meaningful size to harvest
		cheats.assume(amount > 1e18);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);

		cheats.startPrank(alOwner, alOwner);

		assignToUser(alOwner, fakeUnderlyingToken, amount);
		setHarvestableBalance(amount);
		alchemist.harvest(fakeYieldToken, minimumAmountOut(amount, fakeYieldToken));

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYieldToken, fakeUnderlyingToken, minted, burned, sentToTransmuter);
	}
}
