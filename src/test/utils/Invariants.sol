// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {Functionalities} from "./Functionalities.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "alchemix-v2-auditable/interfaces/IAlchemistV2.sol";

contract Invariants is Functionalities {

    /* Invariant A1: Assume all CDPs are fully updated (using _poke) and no rounding errors. */
    /* Let m be the amount of debt tokens minted by the Alchemist, b the amount of debt tokens */
    /* burned by the Alchemist, d the sum of all debts in the Alchemist, and t the amount of */
    /* underlying tokens sent to the TransmuterBuffer from the Alchemist. Then, m = b + d + t. */
    /* Note that if a CDP has credit (negative debt) this amount is subtracted from d. */
    function invariantA1(address[] calldata userList,
                         address yieldToken,
                         uint256 tokensMinted,
                         uint256 tokensBurned,
                         uint256 sentToTransmuer) public {
        emit log("Checking Invariant A1");

        int256 debt;
        uint256 shares;
        uint256 lastAccruedWeight;

        int256 debtsAccured;
        uint256 underlyingInTransmutter;

        for (uint i = 0; i < userList.length; i++) {
            (debt, ) = alchemist.accounts(userList[i]);

            debtsAccured += debt;
        }

        emit log("Eq with state variables");
        emit log_named_int("Tokens minted", int256(tokensMinted));
        emit log_named_int("The sum", int256(tokensBurned) + debtsAccured + int256(sentToTransmuer));
        assertEq(int256(tokensMinted),int256(tokensBurned) + debtsAccured + int256(sentToTransmuer));
    }

    /* Invariant A2: The total number of shares of a yield token is equal to the sum */
    /* of the shares of that yield token over all CDPs. */
    function invariantA2(address[] calldata userList, address yieldToken) public {
        emit log("Checking Invariant A2");

        uint256 totalSharesYearn = alchemist.getYieldTokenParameters(yieldToken).totalShares;
        uint256 sumSharesCDPs;
        uint256 shares;

        // Sum of the shares of that yield token over all CDPs.
        for (uint256 i = 0; i < userList.length; i++) {
            (shares, ) = alchemist.positions(userList[i], yieldToken);
            sumSharesCDPs += shares;
        }

        assertEq(totalSharesYearn, sumSharesCDPs);
    }

    /* Invariant A3: Let b be the balance and t the total number of shares of a given yield token. */
    /* Then, b ≤ t, and b = 0 if and only if t = 0 */
    function invariantA3(address[] calldata userList, address yieldToken) public {
        emit log("Checking Invariant A3");

        IAlchemistV2.YieldTokenParams memory params =
            alchemist.getYieldTokenParameters(yieldToken);

        uint256 balance = params.activeBalance;
        uint256 totalShares = params.totalShares;

        emit log_named_uint("balance", balance);
        emit log_named_uint("totalShares", totalShares);
        assertLe(balance, totalShares);

        bool balanceZero = balance == 0;
        bool sharesZero = totalShares == 0;
        assertTrue(balanceZero == sharesZero);

    }

    /* Invariant A7: Assuming the price of a yield token never drops to 0, the expected value */
    /* of the yield token equals 0 only if its balance equals 0. */
    function invariantA7(address[] calldata userList, address yieldToken) public {
        emit log("Checking Invariant A7");

        uint256 priceYieldToken = yearnAdapter.price();
        IAlchemistV2.YieldTokenParams memory params =
            alchemist.getYieldTokenParameters(yieldToken);

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
    function invariantA8(address[] calldata userList,
                         address yieldToken,
                         address underlyingToken) public {
        emit log("Checking Invariant A8");

        uint256 sumSharesCDPs;
        uint256 shares = 0;

        if (!alchemist.isSupportedYieldToken(yieldToken) ||
            !alchemist.isSupportedUnderlyingToken(underlyingToken)) {

            // Sum of the shares of that yield token over all CDPs.
            for (uint256 i = 0; i < userList.length; i++) {
                (shares, ) = alchemist.positions(userList[i], yieldToken);
                sumSharesCDPs += shares;
            }
        }
        assertEq(sumSharesCDPs, 0);
    }
}
