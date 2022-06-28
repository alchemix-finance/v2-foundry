// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "../../lib/ds-test/src/test.sol";

import {Invariants} from "./utils/Invariants.sol";

contract TestInvariants is Invariants {

    function setUp() public {}

    /*
     * Test that the invariant is preserved by the depositUnderlying operation
     *
     * Values defined as uint96 to restrict the range that the inputs can be
     * fuzzed over: inputs close to 2^128 can cause arithmetic overflows
     */
    function testInvariantOnDeposit(
        address caller, address proxyOwner,
        address[] calldata userList,
        uint96[] calldata debtList,
        uint96[] calldata overCollateralList,
        uint96 amount,
        address recipient
    ) public {
        // Discard an input if it violates assumptions
        ensureConsistency(proxyOwner, userList, debtList, overCollateralList);
        cheats.assume(0 < amount);
        cheats.assume(recipient != address(0));

        // Initialize contracts, tokens and user CDPs
        setScenario(caller, proxyOwner, userList, debtList, overCollateralList);

        // Check that invariant holds before interaction
        invariantA3(userList, fakeYield);

        // Perform an interaction as the first user in the list
        cheats.startPrank(userList[0], userList[0]);

        // Deposit tokens to an arbitrary recipient
        assignToUser(userList[0], fakeUnderlying, amount);
        alchemist.depositUnderlying(
            fakeYield,
            amount,
            recipient,
            minimumAmountOut(amount, fakeYield)
        );

        cheats.stopPrank();

        // Check that invariant holds after interaction
        invariantA3(userList, fakeYield);
    }

    function testInvariantOnWithdraw(
        address caller, address proxyOwner,
        address[] calldata userList,
        uint96[] calldata debtList,
        uint96[] calldata overCollateralList,
        uint96 amount,
        address recipient
    ) public {
        ensureConsistency(proxyOwner, userList, debtList, overCollateralList);
        cheats.assume(0 < amount);
        cheats.assume(recipient != address(0));
        // Ensure first user has enough collateral to withdraw
        cheats.assume(amount <= overCollateralList[0]);

        setScenario(caller, proxyOwner, userList, debtList, overCollateralList);
        
        invariantA3(userList, fakeYield);

        // Calculate how many shares the amount corresponds to
        (uint256 totalShares,) = alchemist.positions(userList[0], fakeYield);
        uint256 totalBalance = calculateBalance(
			debtList[0], overCollateralList[0], fakeUnderlying
		);
		uint256 shares = totalShares * amount / totalBalance;

		cheats.startPrank(userList[0], userList[0]);

		alchemist.withdrawUnderlying(
			fakeYield,
			shares,
			recipient,
			minimumAmountOut(amount, fakeYield)
		);

		cheats.stopPrank();

		invariantA3(userList, fakeYield);
	}
	
}
