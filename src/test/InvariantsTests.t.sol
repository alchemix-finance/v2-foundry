// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import { Invariants } from "./utils/Invariants.sol";

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

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		cheats.startPrank(userList[0], userList[0]);

		// Assign yield tokens to a user
		assignToUser(userList[0], fakeUnderlying, amount);
		assignYieldTokenToUser(userList[0], fakeYield, amount);

		// Deposit yield tokens
		alchemist.deposit(fakeYield, amount, userList[0]);

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
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

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		cheats.startPrank(userList[0], userList[0]);

		// Assign yield tokens to a user
		assignToUser(userList[0], fakeUnderlying, amount);

		// Deposit underlying tokens
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
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

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYield);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlying);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Assign yield tokens to a user
		assignToUser(userList[0], fakeUnderlying, amount);

		// Deposit underlying tokens
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		// Withdraw yield token
		alchemist.withdraw(fakeYield, sharesToWithdraw, recipient);

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
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

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYield);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlying);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Assign yield tokens to a user
		assignToUser(userList[0], fakeUnderlying, amount);

		// Deposit underlying tokens
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		// Withdraw underlying token
		alchemist.withdrawUnderlying(fakeYield, sharesToWithdraw, recipient, minimumAmountOut(amount, fakeYield));

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
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

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYield);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlying);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Assign yield tokens to a user
		assignToUser(userList[0], fakeUnderlying, amount);

		// Deposit underlying tokens
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		// Approve a different account to withdraw
		alchemist.approveWithdraw(userList[1], fakeYield, sharesToWithdraw);

		cheats.stopPrank();

		// Switch to approved account
		cheats.startPrank(userList[1], userList[1]);

		// Withdraw yield from an owner's account
		alchemist.withdrawFrom(userList[0], fakeYield, sharesToWithdraw, recipient);

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
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

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYield);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlying);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Assign yield tokens to a user
		assignToUser(userList[0], fakeUnderlying, amount);

		// Deposit underlying tokens
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		// Approve a different account to withdraw
		alchemist.approveWithdraw(userList[1], fakeYield, sharesToWithdraw);

		cheats.stopPrank();

		// Switch to approved account
		cheats.startPrank(userList[1], userList[1]);

		// Withdraw underlying token from an owner's account
		alchemist.withdrawUnderlyingFrom(
			userList[0],
			fakeYield,
			sharesToWithdraw,
			recipient,
			minimumAmountOut(amount, fakeYield)
		);

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
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

		// Prevent quotient of 0
		cheats.assume(amount > 2);

		// Check that invariant holds before interaction
		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		cheats.startPrank(userList[0], userList[0]);

		assignToUser(userList[0], fakeUnderlying, amount);
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		// Mint debt from an account
		alchemist.mint((amount / 2), userList[0]);
		minted += (amount / 2);

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
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

		// Prevent quotient of 0
		cheats.assume(amount > 2);

		// Check that invariant holds before interaction
		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		cheats.startPrank(userList[0], userList[0]);

		assignToUser(userList[0], fakeUnderlying, amount);
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		// Approve a different account to mint debt
		alchemist.approveMint(userList[1], (amount / 2));

		cheats.stopPrank();

		// Switch to an account to mint from
		cheats.startPrank(userList[1], userList[1]);

		// Mint debt from an owner's account
		alchemist.mintFrom(userList[0], (amount / 2), userList[1]);
		minted += (amount / 2);

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
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

		// Prevent quotient of 0
		cheats.assume(amount > 2);

		// Check that invariant holds before interaction
		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		cheats.startPrank(userList[0], userList[0]);

		assignToUser(userList[0], fakeUnderlying, amount);

		// Get maximum repay limit
		(, , maximum) = alchemist.getRepayLimitInfo(fakeUnderlying);

		// Repay either maximum limit or specific amount of debt
		maximum = (amount / 2) > maximum ? maximum : (amount / 2);
		alchemist.repay(fakeUnderlying, maximum, userList[0]);
		sentToTransmuter += maximum;

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
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

		// Prevent quotient of 0
		cheats.assume(amount > 2);

		// Check that invariant holds before interaction
		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		cheats.startPrank(userList[0], userList[0]);

		assignToUser(userList[0], fakeUnderlying, amount);
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		// Mint debt from an account
		alchemist.mint((amount / 2), userList[0]);
		minted += (amount / 2);

		// Burn debt tokens
		alToken.approve(address(alchemist), amount);
		alchemist.burn((amount / 2), userList[0]);
		burned += (amount / 2);

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
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

		// Prevent quotient of 0
		cheats.assume(amount > 2);

		// Check that invariant holds before interaction
		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		cheats.startPrank(userList[0], userList[0]);

		assignToUser(userList[0], fakeUnderlying, amount);
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		// Mint debt from an account
		alchemist.mint((amount / 2), userList[0]);
		minted += (amount / 2);

		// Get maximum liquidation limit
		(, , maximum) = alchemist.getLiquidationLimitInfo(fakeUnderlying);

		// Liquidate either maximum limit or specific amount
		maximum = (amount / 2) > maximum ? maximum : (amount / 2);
		alchemist.liquidate(fakeYield, maximum, minimumAmountOut(maximum, fakeYield));
		sentToTransmuter += maximum;

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
	}
}
