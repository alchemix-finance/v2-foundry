// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import { Invariants } from "./utils/Invariants.sol";

contract TestInvariants is Invariants {
	function setUp() public {}

	/*
	 * Test that the invariants are preserved by the deposit, depositUnderlying,
	 * withdraw, withdrawFrom, withdrawUnderlying, and withdrawUnderlyingFrom operations
	 *
	 * Values defined as uint96 to restrict the range that the inputs can be
	 * fuzzed over: inputs close to 2^128 can cause arithmetic overflows
	 */
	function testInvariantsOnDepositAndWithdraw(
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

		// Ensure first user has enough collateral to withdraw and prevent quotient of 0
		cheats.assume(amount <= overCollateralList[0] && amount > 8);

		invariantA1(userList, fakeYield, minted, 0, 0);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYield);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlying);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Approve a different account to withdraw
		alchemist.approveWithdraw(userList[1], fakeYield, (sharesToWithdraw / 2));

		// Withdraw underlying token
		alchemist.withdrawUnderlying(fakeYield, (sharesToWithdraw / 2), recipient, minimumAmountOut(amount, fakeYield));

		// Assign underlying tokens to a user
		assignToUser(userList[0], fakeUnderlying, amount);

		// Deposit underlying tokens
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		// Withdraw yield token
		alchemist.withdraw(fakeYield, (sharesToWithdraw / 4), recipient);

		cheats.stopPrank();

		cheats.startPrank(userList[1], userList[1]);

		// Assign yield tokens to a user
		assignToUser(userList[1], fakeUnderlying, amount);
		assignYieldTokenToUser(userList[1], fakeYield, amount);

		// Deposit yield tokens
		alchemist.deposit(fakeYield, amount, userList[1]);

		// Withdraw yield from an owner's account
		alchemist.withdrawFrom(userList[0], fakeYield, (sharesToWithdraw / 4), recipient);

		// Withdraw underlying token from an owner's account
		alchemist.withdrawUnderlyingFrom(
			userList[0],
			fakeYield,
			(sharesToWithdraw / 4),
			recipient,
			minimumAmountOut(amount, fakeYield)
		);

		cheats.stopPrank();

		invariantA1(userList, fakeYield, minted, 0, 0);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
	}

	/*
	 * Test that the invariants are preserved by the mint, mintFrom,
	 * repay, burn, and liquidate operations
	 */
	function testInvariantsOnMintBurnRepayLiquidate(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList,
		uint96 amount,
		address recipient
	) public {
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, amount, recipient);

		// Prevent quotient of 0
		cheats.assume(amount > 10);

		// Check that invariant holds before interaction
		invariantA1(userList, fakeYield, minted, 0, 0);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);

		cheats.startPrank(userList[0], userList[0]);

		assignToUser(userList[0], fakeUnderlying, amount);
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		// Mint debt from an account
		alchemist.mint((amount / 4), userList[0]);
		minted += (amount / 4);

		// Approve a different account to mint debt
		alchemist.approveMint(userList[1], (amount / 4));

		// Burn debt tokens
		alToken.approve(address(alchemist), amount);
		alchemist.burn((amount / 8), userList[0]);
		burned += (amount / 8);

		(, , maximum) = alchemist.getRepayLimitInfo(fakeUnderlying);

		assignToUser(userList[0], fakeUnderlying, amount);

		// Repay either maximum limit or specific amount of debt
		maximum = (amount / 8) > maximum ? maximum : (amount / 8);
		alchemist.repay(fakeUnderlying, maximum, userList[0]);
		sentToTransmuter += maximum;

		cheats.stopPrank();

		cheats.startPrank(userList[1], userList[1]);

		// Mint debt from an owner's account
		alchemist.mintFrom(userList[0], (amount / 4), userList[1]);
		minted += (amount / 4);

		cheats.stopPrank();

		cheats.startPrank(userList[0], userList[0]);

		// Set the amount to liquidate
		(, , maximum) = alchemist.getLiquidationLimitInfo(fakeUnderlying);
		maximum = (amount / 4) > maximum ? maximum : (amount / 4);

		// Liquidate either maximum limit or specific amount of debt
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
