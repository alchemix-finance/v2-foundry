// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.12;

import {console} from "forge-std/console.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "./interfaces/IAlchemistV2.sol";
import {IAaveFlashLoanReceiver} from "./interfaces/IAaveFlashLoanReceiver.sol";
import {IAaveLendingPool} from "./interfaces/IAaveLendingPool.sol";
import {IERC3156FlashLender} from "./interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "./interfaces/IERC3156FlashBorrower.sol";

/// @title A wrapper for single-sided ALCX staking
contract Autoleverage is IERC3156FlashBorrower, IAaveFlashLoanReceiver {

    constructor() {
    }

    function autoleverage(
        address flashLender,
        address alchemist,
        address yieldToken,
        uint amountInitial,
        uint amountTotal,
        address recipient,
        uint minimumAmountOut
    ) external {
        console.log("autoleverage()");
        // Get underlying token from alchemist
        address underlyingToken = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken).underlyingToken;

        uint loanAmount = amountTotal - amountInitial;
        console.log(loanAmount);
        // YieldTokenParams memory _yieldTokenParams = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken);
        // address underlyingToken = _yieldTokenParams.underlyingToken;

        // Flashloan the difference, accounting for fees
        // uint flashAmount = amountTotal - amountInitial;
        // IERC3156FlashLender(flashLender).flashLoan(
        //     IERC3156FlashBorrower(address(this)),
        //     underlyingToken,
        //     flashAmount,
        //     ""
        // );

        // Transfer initial tokens to contract
        IERC20(underlyingToken).transferFrom(msg.sender, address(this), amountInitial);

        // Take out flashloan
        address[] memory assets = new address[](1);
        assets[0] = underlyingToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanAmount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        bytes memory params = abi.encode(
            flashLender,
            alchemist,
            yieldToken,
            recipient
        );
        console.log("flashlender");
        // console.log(params);

        IAaveLendingPool(flashLender).flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(0x0), // onBehalfOf, not used here
            params, // params, not used here
            0 // referralCode
        );

        // uint sharesIssued = IAlchemistV2(alchemist).depositUnderlying(
        //     yieldToken,
        //     flashAmount,
        //     recipient,
        //     minimumAmountOut
        // );
    }

    function executeOperation(
        address[] calldata assets,
        uint[] calldata amounts,
        uint[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {

        console.log("executeOperation");

        (
            address flashLender,
            address alchemist,
            address yieldToken,
            address recipient
        ) = abi.decode(params, (address, address, address, address));

        // Deposit into the alchemsit

        {
            uint balance = IERC20(assets[0]).balanceOf(address(this));
            console.log("balance");
            console.log(balance);
            // Deposit into recipient's account
            IERC20(assets[0]).approve(alchemist, type(uint).max);
            IAlchemistV2(alchemist).depositUnderlying(yieldToken, balance, recipient, 0);

            console.log("deposited");
            uint maxDebt = balance / 2 - 1; // TODO: Get exact max
            // Mint from recipient's account
            IAlchemistV2(alchemist).mintFrom(recipient, maxDebt, address(this));

            // Swap the alAsset for the underlying
            // Have to account for slippage and sandwiching here
            // Do we pass the path?
            // alUSD -> WETH -> 
            address alAsset = IAlchemistV2(alchemist).debtToken();
            uint alBalance = IERC20(alAsset).balanceOf(address(this));
            console.log("alBalance");
            console.log(alBalance);
        }

        {
        uint repayAmount = amounts[0] + premiums[0];
        console.log("repayAmount");
        console.log(repayAmount);
        // Approve the LendingPool contract allowance to *pull* the owed amount
        IERC20(assets[0]).approve(flashLender, repayAmount);
        require(
            IERC20(assets[0]).balanceOf(address(this)) >= repayAmount,
            "Not enough tokens to repay flashloan"
        );
        }

        return true;
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint amount,
        uint fee,
        bytes calldata data
    ) external returns (bytes32) {

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

}