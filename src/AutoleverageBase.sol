// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "./interfaces/IAlchemistV2.sol";
import {IAaveFlashLoanReceiver} from "./interfaces/IAaveFlashLoanReceiver.sol";
import {IAaveLendingPool} from "./interfaces/IAaveLendingPool.sol";

/// @title A zapper for leveraged deposits into the Alchemist
abstract contract AutoleverageBase is IAaveFlashLoanReceiver {

    struct Details {
        address flashLender;
        address pool;
        int128 poolI;
        int128 poolJ;
        address alchemist;
        address yieldToken;
        address recipient;
        uint256 targetDebt;
    }
    
    /// @notice When the yieldToken has no underlyingToken in the alchemist
    error UnsupportedYieldToken(address yieldToken);
    /// @notice When the collateral is insufficient to mint targetDebt
    error MintFailure(); 
    /// @notice When the helper contract ends up with too few or too many tokens
    error InexactTokens(uint256 currentBalance, uint256 repayAmount);

    /// @notice Either convert received eth to weth, or transfer ERC20 from the msg.sender to this contract
    /// @param msgSender msg.sender in outer function
    /// @param msgValue msg.value in outer function
    /// @param underlyingToken The ERC20 desired to transfer
    /// @param collateralInitial The amount of tokens taken from the user
    function _transferTokensToSelf(address msgSender, uint msgValue, address underlyingToken, uint collateralInitial) internal virtual;

    /// @notice Convert received eth to weth, or do nothing
    /// @param amountOut The amount received from the curve swap
    function _maybeConvertCurveOutput(uint amountOut) internal virtual;

    /// @notice Swap on curve using the supplied params
    /// @param poolAddress Curve pool address
    /// @param debtToken The alAsset debt token address
    /// @param i Curve swap param
    /// @param j Curve swap param
    /// @param minAmountOut Minimum amount received from swap
    /// @return amountOut The actual amount received from swap
    function _curveSwap(address poolAddress, address debtToken, int128 i, int128 j, uint256 minAmountOut) internal virtual returns (uint256 amountOut);

    /// @notice Approve a contract to spend tokens
    /// @dev Callable by anyone to top-up new alchemists
    function approve(address token, address spender) public {
        IERC20(token).approve(spender, type(uint256).max);
    }

    /// @notice Transfer tokens from msg.sender here, then call flashloan which calls callback
    /// @dev Must have targetDebt > collateralTotal - collateralInitial, otherwise flashloan payback will fail
    /// @param flashLender The address of the Aave V2 lending pool
    /// @param pool The address of the curve pool to swap on
    /// @param poolI The `i` param for the curve swap
    /// @param poolJ The `j` param for the curve swap
    /// @param alchemist The alchemist to deposit and mint from
    /// @param yieldToken The yieldToken to convert deposits into
    /// @param collateralInitial The amount of tokens that will be taken from the user
    /// @param collateralTotal The amount of tokens that will be deposited as collateral for the user
    /// @param targetDebt The amount of debt that the user will incur
    /// @param recipient The user to perform actions on, can be different from msg.sender since msg.sender is paying for it
    function autoleverage(
        address flashLender,
        address pool,
        int128 poolI,
        int128 poolJ,
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

        _transferTokensToSelf(msg.sender, msg.value, underlyingToken, collateralInitial);

        // Take out flashloan
        address[] memory assets = new address[](1);
        assets[0] = underlyingToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = collateralTotal - collateralInitial;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        bytes memory params = abi.encode(Details({
            flashLender: flashLender,
            pool: pool,
            poolI: poolI,
            poolJ: poolJ,
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

    /// @notice Flashloan callback receiver, will be called by IAaveLendingPool.flashloan()
    /// @dev Never call this function directly
    /// @param assets An array of length 1, pointing to the ERC20 received in the flashloan
    /// @param amounts An array of length 1, with the ERC20 amount received in the flashloan
    /// @param premiums An array of length 1, with the flashloan fee. We will pay back amounts[0] + premiums[0] to the flashloan provider
    /// @param initiator Points to who initiated the flashloan, not used
    /// @param params ABI-encoded `Details` struct containing many details about desired functionality
    /// @return success Always true unless reverts, required by Aave flashloan
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
        approve(assets[0], details.alchemist);
        IAlchemistV2(details.alchemist).depositUnderlying(details.yieldToken, collateralBalance, details.recipient, 0);

        // Mint from recipient's account
        try IAlchemistV2(details.alchemist).mintFrom(details.recipient, details.targetDebt, address(this)) {

        } catch {
            revert MintFailure();
        }

        address debtToken = IAlchemistV2(details.alchemist).debtToken();
        uint amountOut = _curveSwap(
            details.pool, 
            debtToken, 
            details.poolI, 
            details.poolJ, 
            repayAmount
        );

        _maybeConvertCurveOutput(amountOut);

        // Deposit excess assets into the alchemist on behalf of the user
        uint256 excessCollateral = amountOut - repayAmount;
        if (excessCollateral > 0) {
            IAlchemistV2(details.alchemist).depositUnderlying(details.yieldToken, excessCollateral, details.recipient, 0);
        }

        // Approve the LendingPool contract allowance to *pull* the owed amount
        approve(assets[0], details.flashLender);
        uint256 balance = IERC20(assets[0]).balanceOf(address(this));
        if (balance != repayAmount) {
            revert InexactTokens(balance, repayAmount);
        }

        return true;
    }

}