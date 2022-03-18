// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {console} from "forge-std/console.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "./interfaces/IAlchemistV2.sol";
import {IAaveFlashLoanReceiver} from "./interfaces/IAaveFlashLoanReceiver.sol";
import {IAaveLendingPool} from "./interfaces/IAaveLendingPool.sol";
import {ICurveMetapool} from "./interfaces/ICurveMetapool.sol";

/// @title A zapper for DAI deposits into the alUSD pool
contract Autoleverage is IAaveFlashLoanReceiver {

    address alusd3crvMetapool = 0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c;

    struct Details {
        address flashLender;
        address alchemist;
        address yieldToken;
        address recipient;
        uint targetDebt;
        uint repayAmount;
    }
    
    error InexactTokens(uint currentBalance, uint repayAmount);

    // @notice Transfer tokens from msg.sender here, then call flashloan which calls callback
    function autoleverage(
        address flashLender,
        address alchemist,
        address yieldToken,
        uint collateralInitial,
        uint collateralTotal,
        uint targetDebt,
        address recipient
    ) external {
        console.log("autoleverage()");
        // Get underlying token from alchemist
        address underlyingToken = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken).underlyingToken;

        // Transfer initial tokens to contract
        console.log("transferFrom(collateralInitial)");
        IERC20(underlyingToken).transferFrom(msg.sender, address(this), collateralInitial);

        // Take out flashloan
        address[] memory assets = new address[](1);
        assets[0] = underlyingToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = collateralTotal - collateralInitial;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        bytes memory params = abi.encode(Details({
            flashLender: flashLender,
            alchemist: alchemist,
            yieldToken: yieldToken,
            recipient: recipient,
            targetDebt: targetDebt,
            repayAmount: 0
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

        console.log("executeOperation()");
        Details memory details;

        {
            details = abi.decode(params, (Details));
            details.repayAmount = amounts[0] + premiums[0];
            console.log("repayAmount:");
            console.log(details.repayAmount / 1 ether);
        }

        {
            uint collateralBalance = IERC20(assets[0]).balanceOf(address(this));

            console.log("collateralBalance:");
            console.log(collateralBalance / 1 ether);
            // Deposit into recipient's account
            IERC20(assets[0]).approve(details.alchemist, type(uint).max);
            IAlchemistV2(details.alchemist).depositUnderlying(details.yieldToken, collateralBalance, details.recipient, 0);

            // Mint from recipient's account
            console.log("mintFrom()");
            IAlchemistV2(details.alchemist).mintFrom(details.recipient, details.targetDebt, address(this));
        }

        console.log("Success: deposit and mintFrom");

        {
            address alAsset = IAlchemistV2(details.alchemist).debtToken();
            uint alBalance = IERC20(alAsset).balanceOf(address(this));
            console.log("alBalance:");
            console.log(alBalance / 1 ether);

            // Curve swap
            IERC20(alAsset).approve(alusd3crvMetapool, type(uint).max);
            console.log("exchange_underlying()");
            uint amountOut = ICurveMetapool(alusd3crvMetapool).exchange_underlying(
                0, // index of coin to send (alUSD)
                1, // index of coin to receive (DAI)
                alBalance, // amountIn
                details.repayAmount // TODO: populate this with offchain calculations using slippage params
            );
            console.log("amountOut:");
            console.log(amountOut / 1 ether);

            // Deposit excess assets into the alchemist on behalf of the user
            uint excessCollateral = amountOut - details.repayAmount;
            IAlchemistV2(details.alchemist).depositUnderlying(details.yieldToken, excessCollateral, details.recipient, 0);
        }

        {
            // Approve the LendingPool contract allowance to *pull* the owed amount
            IERC20(assets[0]).approve(details.flashLender, details.repayAmount);
            uint balance = IERC20(assets[0]).balanceOf(address(this));
            if (balance != details.repayAmount) {
                revert InexactTokens(balance, details.repayAmount);
            }
        }

        return true;
    }

}