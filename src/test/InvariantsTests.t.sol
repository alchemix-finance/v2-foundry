// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "../../lib/ds-test/src/test.sol";

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
		uint96 priceIncrease,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, amount, recipient);

		// Ensure first user has enough underlying token
		cheats.assume(amount >= tokenAdapter.price());

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		// Assign yield tokens to a user
		assignToUser(userList[0], fakeUnderlying, amount);
		uint256 yieldAmount = assignYieldTokenToUser(userList[0], fakeYield, amount);

		// Deposit yield tokens
		alchemist.deposit(fakeYield, yieldAmount, userList[0]);

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);
		invariantA4(userList[0], fakeYield);
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
		uint96 priceIncrease,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, amount, recipient);

		// Ensure first user has enough underlying token
		cheats.assume(amount >= tokenAdapter.price());

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		// Assign yield tokens to a user
		assignToUser(userList[0], fakeUnderlying, amount);

		// Deposit underlying tokens
		alchemist.depositUnderlying(fakeYield, amount, userList[0], minimumAmountOut(amount, fakeYield));

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);
		invariantA4(userList[0], fakeYield);
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
		uint96 priceIncrease,
		uint96 baseAmount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, baseAmount, recipient);

		// Avoid undercollateralization due to rounding errors
		uint256 amount = baseAmount + tokenAdapter.price();

		// Ensure first user has enough collateral to withdraw
		cheats.assume(amount <= overCollateralList[0]);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYield);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlying);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Withdraw yield token
		alchemist.withdraw(fakeYield, sharesToWithdraw, recipient);

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);
		invariantA4(userList[0], fakeYield);
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
		uint96 priceIncrease,
		uint96 baseAmount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, baseAmount, recipient);

		// Avoid undercollateralization due to rounding errors
		uint256 amount = baseAmount + tokenAdapter.price();

		// Ensure first user has enough collateral to withdraw
		cheats.assume(amount <= overCollateralList[0]);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYield);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlying);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Withdraw underlying token
		alchemist.withdrawUnderlying(fakeYield, sharesToWithdraw, recipient, minimumAmountOut(amount, fakeYield));

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);
		invariantA4(userList[0], fakeYield);
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
		uint96 priceIncrease,
		uint96 baseAmount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, baseAmount, recipient);

		// Avoid undercollateralization due to rounding errors
		uint256 amount = baseAmount + tokenAdapter.price();

		// Ensure first user has enough collateral to withdraw
		cheats.assume(amount <= overCollateralList[0]);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYield);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlying);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		// Approve a different account to withdraw
		alchemist.approveWithdraw(userList[1], fakeYield, sharesToWithdraw);

		cheats.stopPrank();

		// Switch to approved account
		cheats.startPrank(userList[1], userList[1]);

		// Withdraw yield from an owner's account
		alchemist.withdrawFrom(userList[0], fakeYield, sharesToWithdraw, recipient);

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);
		invariantA4(userList[0], fakeYield);
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
		uint96 priceIncrease,
		uint96 baseAmount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, baseAmount, recipient);

		// Avoid undercollateralization due to rounding errors
		uint256 amount = baseAmount + tokenAdapter.price();

		// Ensure first user has enough collateral to withdraw
		cheats.assume(amount <= overCollateralList[0]);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);

		// Calculate how many shares to withdraw
		(uint256 totalShares, ) = alchemist.positions(userList[0], fakeYield);
		uint256 totalBalance = calculateBalance(debtList[0], overCollateralList[0], fakeUnderlying);
		uint256 sharesToWithdraw = (totalShares * amount) / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

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

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);
		invariantA4(userList[0], fakeYield);
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
		uint96 priceIncrease,
		uint96 baseAmount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, baseAmount, recipient);

		// Avoid undercollateralization due to rounding errors
		uint256 amount = baseAmount + tokenAdapter.price();

		// Ensure first user has enough collateral to mint
		cheats.assume(amount <= (overCollateralList[0] / 2));

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		// Mint debt from an account
		alchemist.mint(amount, userList[0]);
		minted += amount;

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);
		invariantA4(userList[0], fakeYield);
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
		uint96 priceIncrease,
		uint96 baseAmount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, baseAmount, recipient);

		// Avoid undercollateralization due to rounding errors
		uint256 amount = baseAmount + tokenAdapter.price();

		// Ensure first user has enough collateral to mint
		cheats.assume(amount <= (overCollateralList[0] / 2));

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);

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
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);
		invariantA4(userList[0], fakeYield);
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
		uint96 priceIncrease,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, amount, recipient);

		// Ensure account has debt to repay
		cheats.assume(debtList[0] > 0);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		uint256 repayAmount = setRepayAmount(userList[0], fakeUnderlying, amount);

		alchemist.repay(fakeUnderlying, repayAmount, userList[0]);

		// Maximum amount that can be repaid is the account's total debt
		sentToTransmuter += ((repayAmount > debtList[0]) ? debtList[0] : repayAmount);

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);
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
		uint96 priceIncrease,
		uint96 amount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, amount, recipient);

		// Ensure account has debt to burn
		cheats.assume(debtList[0] > 0);

		// Check that invariants hold before interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);

		cheats.startPrank(userList[0], userList[0]);

		// Burn debt tokens
		alToken.approve(address(alchemist), debtList[0]);
		alchemist.burn(debtList[0], userList[0]);
		burned += debtList[0];

		cheats.stopPrank();

		// Check that invariants hold after interaction
		checkAllInvariants(userList, fakeYield, fakeUnderlying, minted, burned, sentToTransmuter);
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
		uint96 priceIncrease,
		uint96 baseAmount,
		address recipient
	) public {
		// Initialize the test
		setupTest(caller, proxyOwner, userList, debtList, overCollateralList, priceIncrease, baseAmount, recipient);

		// Ensure account has debt to liquidate
		cheats.assume(debtList[0] >= tokenAdapter.price());

		// Check that invariants hold before interaction
		invariantA1Range(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
		invariantA9(userList, fakeYield, fakeUnderlying);

		cheats.startPrank(userList[0], userList[0]);

		uint256 amount = baseAmount + tokenAdapter.price();

		uint256 liquidationAmount = setLiquidationAmount(fakeUnderlying, amount);

		alchemist.liquidate(fakeYield, liquidationAmount, minimumAmountOut(liquidationAmount, fakeYield));
		sentToTransmuter += liquidationAmount;

		cheats.stopPrank();

		// Check that invariants hold after interaction
		invariantA1Range(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA4(userList[0], fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
		invariantA9(userList, fakeYield, fakeUnderlying);
	}
}
