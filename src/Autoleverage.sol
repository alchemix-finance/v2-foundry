// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {console} from "forge-std/console.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "./interfaces/IAlchemistV2.sol";
import {IAaveFlashLoanReceiver} from "./interfaces/IAaveFlashLoanReceiver.sol";
import {IAaveLendingPool} from "./interfaces/IAaveLendingPool.sol";
import {ICurveMetapool} from "./interfaces/ICurveMetapool.sol";
import {IERC3156FlashLender} from "./interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "./interfaces/IERC3156FlashBorrower.sol";

/// @title A wrapper for single-sided ALCX staking
contract Autoleverage is IERC3156FlashBorrower, IAaveFlashLoanReceiver {

    address alusd3crvMetapool = 0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c;

    struct Details {
        address flashLender;
        address alchemist;
        address yieldToken;
        address recipient;
    }

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

        // Transfer initial tokens to contract
        console.log("transferFrom(amountInitial)");
        IERC20(underlyingToken).transferFrom(msg.sender, address(this), amountInitial);

        // Take out flashloan
        address[] memory assets = new address[](1);
        assets[0] = underlyingToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanAmount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        bytes memory params = abi.encode(Details({
            flashLender: flashLender,
            alchemist: alchemist,
            yieldToken: yieldToken,
            recipient: recipient
        }));
        console.log("flashLoan()");

        IAaveLendingPool(flashLender).flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(0x0), // onBehalfOf, not used here
            params, // params, not used here
            0 // referralCode
        );
    }

    function executeOperation(
        address[] calldata assets,
        uint[] calldata amounts,
        uint[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {

        console.log("executeOperation");

        Details memory details;
        
        {
        details = abi.decode(params, (Details));
        }

        {
            uint collateralBalance = IERC20(assets[0]).balanceOf(address(this));
            uint targetDebt = collateralBalance / 2 - 1; // TODO: Get exact max

            console.log("collateralBalance");
            console.log(collateralBalance);
            // Deposit into recipient's account
            IERC20(assets[0]).approve(details.alchemist, type(uint).max);
            IAlchemistV2(details.alchemist).depositUnderlying(details.yieldToken, collateralBalance, details.recipient, 0);

            // Mint from recipient's account
            IAlchemistV2(details.alchemist).mintFrom(details.recipient, targetDebt, address(this));
        }

        {
            address alAsset = IAlchemistV2(details.alchemist).debtToken();
            uint alBalance = IERC20(alAsset).balanceOf(address(this));
            console.log("alBalance");
            console.log(alBalance);

            // Curve swap
            IERC20(alAsset).approve(alusd3crvMetapool, type(uint).max);
            console.log("exchange_underlying()");
            uint amountOut = ICurveMetapool(alusd3crvMetapool).exchange_underlying(
                0, // index of coin to send (alUSD)
                1, // index of coin to receive (DAI)
                alBalance, // amountIn
                // 0
                // amounts[0] + premiums[0] // minAmountOut
                amounts[0]
            );
            console.log(amountOut);
        }

        {
        uint repayAmount = amounts[0] + premiums[0];
        console.log("repayAmount");
        console.log(repayAmount);
        // Approve the LendingPool contract allowance to *pull* the owed amount
        IERC20(assets[0]).approve(details.flashLender, repayAmount);
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