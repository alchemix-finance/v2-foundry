// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "./interfaces/IAlchemistV2.sol";
import {IAaveFlashLoanReceiver} from "./interfaces/IAaveFlashLoanReceiver.sol";
import {IAaveLendingPool} from "./interfaces/IAaveLendingPool.sol";
import {ICurveFactoryethpool} from "./interfaces/ICurveFactoryethpool.sol";
import {IWETH9} from "./interfaces/external/IWETH9.sol";

/// @title A zapper for leveraged deposits into the Alchemist
contract AutoleverageCurveFactoryethpool is IAaveFlashLoanReceiver {

    address public constant wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    struct Details {
        address flashLender;
        address factoryethpool;
        int128 factoryethpoolI;
        int128 factoryethpoolJ;
        address alchemist;
        address yieldToken;
        address recipient;
        uint256 targetDebt;
    }
    
    error IncorrectEthAmount(); // when the eth msg.value doesn't match the initialCollateral
    error UnsupportedYieldToken(address yieldToken); // when the yieldToken has no underlyingToken in the alchemist
    error MintFailure(); // when the collateral is insufficient to mint targetDebt
    error InexactTokens(uint256 currentBalance, uint256 repayAmount); // when the helper contract ends up with too few or too many tokens

    /// @notice Used to receive ETH from factory pool swaps
    fallback() external payable {}

    /// @notice Transfer tokens from msg.sender here, then call flashloan which calls callback
    function autoleverage(
        address flashLender,
        address factoryethpool,
        int128 factoryethpoolI,
        int128 factoryethpoolJ,
        address alchemist,
        address yieldToken,
        uint256 collateralInitial,
        uint256 collateralTotal,
        uint256 targetDebt,
        address recipient
    ) external payable {
        // Get underlying token from alchemist
        address underlyingToken = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken).underlyingToken;
        if (underlyingToken == address(0x0)) revert UnsupportedYieldToken(yieldToken);

        // Convert eth to weth if received eth, otherwise transfer weth
        if (msg.value > 0) {
            if (msg.value != collateralInitial) revert IncorrectEthAmount();
            IWETH9(wethAddress).deposit{value: msg.value}();
        } else {
            IERC20(underlyingToken).transferFrom(msg.sender, address(this), collateralInitial);
        }

        // Take out flashloan
        address[] memory assets = new address[](1);
        assets[0] = underlyingToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = collateralTotal - collateralInitial;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        bytes memory params = abi.encode(Details({
            flashLender: flashLender,
            factoryethpool: factoryethpool,
            factoryethpoolI: factoryethpoolI,
            factoryethpoolJ: factoryethpoolJ,
            alchemist: alchemist,
            yieldToken: yieldToken,
            recipient: recipient,
            targetDebt: targetDebt
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

        Details memory details = abi.decode(params, (Details));
        uint256 repayAmount = amounts[0] + premiums[0];

        uint256 collateralBalance = IERC20(assets[0]).balanceOf(address(this));

        // Deposit into recipient's account
        IERC20(assets[0]).approve(details.alchemist, type(uint256).max);
        IAlchemistV2(details.alchemist).depositUnderlying(details.yieldToken, collateralBalance, details.recipient, 0);

        // Mint from recipient's account
        try IAlchemistV2(details.alchemist).mintFrom(details.recipient, details.targetDebt, address(this)) {

        } catch {
            revert MintFailure();
        }
        
        address debtToken = IAlchemistV2(details.alchemist).debtToken();
        uint256 debtTokenBalance = IERC20(debtToken).balanceOf(address(this));

        // Curve swap
        IERC20(debtToken).approve(details.factoryethpool, type(uint).max);
        uint256 amountOut = ICurveFactoryethpool(details.factoryethpool).exchange(
            details.factoryethpoolI,
            details.factoryethpoolJ,
            debtTokenBalance, // amountIn
            repayAmount // minAmountOut
        );

        // Convert ETH output from Curve into WETH
        IWETH9(wethAddress).deposit{value: amountOut}();

        // Deposit excess assets into the alchemist on behalf of the user
        uint256 excessCollateral = amountOut - repayAmount;
        IAlchemistV2(details.alchemist).depositUnderlying(details.yieldToken, excessCollateral, details.recipient, 0);

        // Approve the LendingPool contract allowance to *pull* the owed amount
        IERC20(assets[0]).approve(details.flashLender, repayAmount);
        uint256 balance = IERC20(assets[0]).balanceOf(address(this));
        if (balance != repayAmount) {
            revert InexactTokens(balance, repayAmount);
        }

        return true;
    }

}