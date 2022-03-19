// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "./interfaces/IAlchemistV2.sol";
import {IAaveFlashLoanReceiver} from "./interfaces/IAaveFlashLoanReceiver.sol";
import {IAaveLendingPool} from "./interfaces/IAaveLendingPool.sol";
import {ICurveMetapool} from "./interfaces/ICurveMetapool.sol";

/// @title A zapper for DAI deposits into the alUSD pool
contract AutoleverageCurveMetapool is IAaveFlashLoanReceiver {

    address public constant flashLender = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;

    struct Details {
        address metapool;
        int128 metapoolI;
        int128 metapoolJ;
        address alchemist;
        address yieldToken;
        address recipient;
        uint256 targetDebt;
        uint256 repayAmount;
    }
    
    error MintFailure(); // when the collateral is insufficient to mint targetDebt
    error InexactTokens(uint256 currentBalance, uint256 repayAmount); // when the helper contract ends up with too few or too many tokens

    // @notice Transfer tokens from msg.sender here, then call flashloan which calls callback
    function autoleverage(
        address metapool,
        int128 metapoolI,
        int128 metapoolJ,
        address alchemist,
        address yieldToken,
        uint256 collateralInitial,
        uint256 collateralTotal,
        uint256 targetDebt,
        address recipient
    ) external {
        // Get underlying token from alchemist
        address underlyingToken = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken).underlyingToken;

        // Transfer initial tokens to contract
        IERC20(underlyingToken).transferFrom(msg.sender, address(this), collateralInitial);

        // Take out flashloan
        address[] memory assets = new address[](1);
        assets[0] = underlyingToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = collateralTotal - collateralInitial;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        bytes memory params = abi.encode(Details({
            metapool: metapool,
            metapoolI: metapoolI,
            metapoolJ: metapoolJ,
            alchemist: alchemist,
            yieldToken: yieldToken,
            recipient: recipient,
            targetDebt: targetDebt,
            repayAmount: 0
        }));

        IAaveLendingPool(flashLender).flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(0x0), // onBehalfOf, not used here
            params, // params, passed to callback func to decode as struct
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

        Details memory details;

        {
            details = abi.decode(params, (Details));
            details.repayAmount = amounts[0] + premiums[0];
        }

        {
            uint256 collateralBalance = IERC20(assets[0]).balanceOf(address(this));

            // Deposit into recipient's account
            IERC20(assets[0]).approve(details.alchemist, type(uint256).max);
            IAlchemistV2(details.alchemist).depositUnderlying(details.yieldToken, collateralBalance, details.recipient, 0);

            // Mint from recipient's account
            try IAlchemistV2(details.alchemist).mintFrom(details.recipient, details.targetDebt, address(this)) {

            } catch {
                revert MintFailure();
            }
            
        }

        {
            address debtToken = IAlchemistV2(details.alchemist).debtToken();
            uint256 debtTokenBalance = IERC20(debtToken).balanceOf(address(this));

            // Curve swap
            IERC20(debtToken).approve(details.metapool, type(uint).max);
            uint256 amountOut = ICurveMetapool(details.metapool).exchange_underlying(
                details.metapoolI,
                details.metapoolJ,
                debtTokenBalance, // amountIn
                details.repayAmount // TODO: populate this with offchain calculations using slippage params
            );

            // Deposit excess assets into the alchemist on behalf of the user
            uint256 excessCollateral = amountOut - details.repayAmount;
            IAlchemistV2(details.alchemist).depositUnderlying(details.yieldToken, excessCollateral, details.recipient, 0);
        }

        {
            // Approve the LendingPool contract allowance to *pull* the owed amount
            IERC20(assets[0]).approve(flashLender, details.repayAmount);
            uint256 balance = IERC20(assets[0]).balanceOf(address(this));
            if (balance != details.repayAmount) {
                revert InexactTokens(balance, details.repayAmount);
            }
        }

        return true;
    }

}