// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import { Functionalities } from "./Functionalities.sol";

import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { AlchemistV2 } from "../../AlchemistV2.sol";

contract Invariants is Functionalities {
	/* Invariant A1: Assume all CDPs are fully updated (using _poke) and no rounding errors. */
	/* Let m be the amount of debt tokens minted by the Alchemist, b the amount of debt tokens */
	/* burned by the Alchemist, d the sum of all debts in the Alchemist, and t the amount of */
	/* underlying tokens sent to the TransmuterBuffer from the Alchemist. Then, m = b + d + t. */
	/* Note that if a CDP has credit (negative debt) this amount is subtracted from d. */
	function invariantA1(
		address[] calldata userList,
		address yieldToken,
		uint256 tokensMinted,
		uint256 tokensBurned,
		uint256 sentToTransmuter
	) public {
		emit log("Checking Invariant A1");

		int256 debt;
		uint256 shares;
		uint256 lastAccruedWeight;

		int256 debtsAccured;
		uint256 underlyingInTransmutter;

		for (uint256 i = 0; i < userList.length; i++) {
			(debt, ) = alchemist.accounts(userList[i]);
			debtsAccured += debt;
		}

		emit log("Eq with state variables");
		emit log_named_int("Tokens minted", int256(tokensMinted));
		emit log_named_int("Debts accured", debtsAccured);
		emit log_named_int("The sum", int256(tokensBurned) + debtsAccured + int256(sentToTransmuter));
		assertEq(int256(tokensMinted), int256(tokensBurned) + debtsAccured + int256(sentToTransmuter));
	}

	/* Invariant A2: The total number of shares of a yield token is equal to the sum */
	/* of the shares of that yield token over all CDPs. */
	function invariantA2(address[] calldata userList, address yieldToken) public {
		emit log("Checking Invariant A2");

		uint256 totalShares = alchemist.getYieldTokenParameters(yieldToken).totalShares;
		uint256 sumSharesCDPs;
		uint256 shares;

		// Sum of the shares of that yield token over all CDPs.
		for (uint256 i = 0; i < userList.length; i++) {
			(shares, ) = alchemist.positions(userList[i], yieldToken);
			sumSharesCDPs += shares;
		}

		assertEq(totalShares, sumSharesCDPs);
	}

	/* Invariant A3: Let b be the balance and t the total number of shares of a given yield token. */
	/* Then, b ≤ t, and b = 0 if and only if t = 0 */
	function invariantA3(address[] calldata userList, address yieldToken) public {
		emit log("Checking Invariant A3");

		AlchemistV2.YieldTokenParams memory params = alchemist.getYieldTokenParameters(yieldToken);

		uint256 balance = params.activeBalance + params.harvestableBalance;
		uint256 totalShares = params.totalShares;

		assertLe(balance, totalShares);

		bool balanceIsZero = balance == 0;
		bool sharesIsZero = totalShares == 0;
		assertTrue(balanceIsZero == sharesIsZero);
	}

    /* Invariant A4: Unless the token has suffered a loss, every operation that changes */ 
    /* the balance or expected value of a yield token leaves the expected value equal to */
    /* the current value, caculated by multiplying the price of the token by its balance. */
    function invariantA4(address user, address yieldToken) public {
        emit log("Checking Invariant A4");
        
        uint256 priceYieldToken = tokenAdapter.price();
        AlchemistV2.YieldTokenParams memory params = 
            alchemist.getYieldTokenParameters(yieldToken);

        uint256 expectedValue = params.expectedValue * 10**params.decimals;
        uint256 currentValue = params.activeBalance * priceYieldToken;

		emit log_named_uint("Expected Value", expectedValue);
		emit log_named_uint("Active Balance", params.activeBalance);
		emit log_named_uint("Price", priceYieldToken);
		emit log_named_uint("Current Value", currentValue);
        assertEq(expectedValue, currentValue);        
    }

	/* Invariant A7: Assuming the price of a yield token never drops to 0, the expected value */
	/* of the yield token equals 0 only if its balance equals 0. */
	function invariantA7(address[] calldata userList, address yieldToken) public {
		emit log("Checking Invariant A7");

		uint256 priceYieldToken = tokenAdapter.price();
		AlchemistV2.YieldTokenParams memory params = alchemist.getYieldTokenParameters(yieldToken);

		if (priceYieldToken != 0) {
			if (params.expectedValue == 0) {
				emit log_named_uint("expectedValue", params.expectedValue);
				emit log_named_uint("activeBalance", params.activeBalance);
				assertEq(params.activeBalance, 0);
			}
		}
	}

	/* Invariant A8: If a yield token or its underlying token is not supported in the protocol, */
	/* then no user has any balance in that yield token. */
	function invariantA8(
		address[] calldata userList,
		address yieldToken,
		address underlyingToken
	) public {
		emit log("Checking Invariant A8");

		uint256 sumSharesCDPs;
		uint256 shares = 0;

		if (!alchemist.isSupportedYieldToken(yieldToken) || !alchemist.isSupportedUnderlyingToken(underlyingToken)) {
			// Sum of the shares of that yield token over all CDPs.
			for (uint256 i = 0; i < userList.length; i++) {
				(shares, ) = alchemist.positions(userList[i], yieldToken);
				sumSharesCDPs += shares;
			}
		}
		assertEq(sumSharesCDPs, 0);
	}

	/* Invariant A9: Assume no loss occurs on yield tokens. Then, every CDP (after being */
    /* updated by _poke) is always "healthy", meaning it maintains at least the minimum */
    /* collateralization ratio (assuming this ratio is at least 1). */
    function invariantA9(address[] calldata userList, 
                         address yieldToken, 
                         address underlyingToken) public {
        emit log("Checking Invariant A9");

        int256 debt;
        address[] memory depositedTokens;
        uint256 shares;
        uint256 amountYieldToken;
        uint256 currentValue;
        uint256 normalizedValue;
        uint256 totalValueCDP = 0;
        uint256 priceYieldToken = tokenAdapter.price(); 
        
        for (uint256 i = 0; i < userList.length; i++) {
            (debt, depositedTokens) = alchemist.accounts(userList[i]);

            // Sum of a CDP's collateral.
            for (uint256 j = 0; j < depositedTokens.length; j++){            
                yieldToken = depositedTokens[j];                
                (shares, ) = alchemist.positions(userList[i], yieldToken);

                AlchemistV2.YieldTokenParams memory yieldTokenParams =
                    alchemist.getYieldTokenParameters(yieldToken);
                
                underlyingToken = yieldTokenParams.underlyingToken;

                AlchemistV2.UnderlyingTokenParams memory underlyingTokenParams =
                    alchemist.getUnderlyingTokenParameters(underlyingToken);
                                  
                amountYieldToken = yieldTokenParams.activeBalance * shares / yieldTokenParams.totalShares;
                currentValue = amountYieldToken * priceYieldToken / 10**yieldTokenParams.decimals;

                // Conversion factor used to normalize the token to a value comparable to the debt token.
                normalizedValue = currentValue * underlyingTokenParams.conversionFactor;
                
                totalValueCDP += normalizedValue;
            }

            if (debt > 0) {        
                uint256 collateralization = totalValueCDP * 1e18 / uint256(debt);
                bool healthyCDP = collateralization >= alchemist.minimumCollateralization();
                assertTrue(healthyCDP);
            }            
        }
    }    

	function checkAllInvariants(
		address[] calldata userList,
		address fakeYield,
		address fakeUnderlying,
		uint256 minted,
		uint256 burned,
		uint256 sentToTransmuter
	) public {
		invariantA1(userList, fakeYield, minted, burned, sentToTransmuter);
		invariantA2(userList, fakeYield);
		invariantA3(userList, fakeYield);
		invariantA7(userList, fakeYield);
		invariantA8(userList, fakeYield, fakeUnderlying);
		invariantA9(userList, fakeYield, fakeUnderlying);
	}

	/* Invariant A1 with range assertions to account for rounding errors
	 * Assert a range of 1000 wei
	 */
	function invariantA1Range(
		address[] calldata userList,
		address yieldToken,
		uint256 tokensMinted,
		uint256 tokensBurned,
		uint256 sentToTransmuter
	) public {
		emit log("Checking Invariant A1 Range");

		int256 debt;
		uint256 shares;
		uint256 lastAccruedWeight;

		int256 debtsAccured;
		uint256 underlyingInTransmutter;

		for (uint256 i = 0; i < userList.length; i++) {
			(debt, ) = alchemist.accounts(userList[i]);
			debtsAccured += debt;
		}

		int256 sum = int256(tokensBurned) + debtsAccured + int256(sentToTransmuter);

		emit log("Eq with state variables");
		emit log_named_int("Tokens minted", int256(tokensMinted));
		emit log_named_int("Debts accured", debtsAccured);
		emit log_named_int("The sum", sum);
		assertLe(int256(tokensMinted), sum);
		assertGt(int256(tokensMinted), sum - 1000);
	}
}
