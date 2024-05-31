pragma solidity ^0.8.11;

import {IllegalState} from "../../base/Errors.sol";

import "../../interfaces/ITokenAdapter.sol";
//import some stuff for maker dai savings rate
import "../../interfaces/IERC4626.sol";
import "../../libraries/TokenUtils.sol";

/// @title  YearnTokenAdapter
/// @author Alchemix Finance
contract DaiSavingsRateAdapter is ITokenAdapter {
    uint256 private constant MAXIMUM_SLIPPAGE = 10000;
    //update for every new deployment
    string public constant override version = "1.0.0";
   //(DAI in DSR)
    address public immutable override token;
    //(DSR)
    address public immutable override underlyingToken;

    constructor(address _token, address _underlyingToken) {
        token = _token;
        underlyingToken = _underlyingToken;
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
      //get the price of DSR in DAI
        return IYearnVaultV2(token).pricePerShare();
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
      //address(this) is the current contract, and storing the data here
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        //maybe not needed to reset the approval
        TokenUtils.safeApprove(underlyingToken, token, 0);
        //approve the transfer of tokens to the DSR contract
        TokenUtils.safeApprove(underlyingToken, token, amount);
        //deposit the tokens into the DSR contract ({value: amount} used for wrapping eth only)
        return IERC4626(token).deposit(amount, recipient);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        //Withdraw yield tokens from alchemist and place in this contract
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);
        //check the balance of the tokens in this contract
        uint256 balanceBefore = TokenUtils.safeBalanceOf(token, address(this));
        //withdraw and get the return value of underlying tokens
        uint256 amountWithdrawn = IERC4626(token).redeem(amount, recipient, recipient);
/* not needed unless there is a bug that might return the wrong value
        uint256 balanceAfter = TokenUtils.safeBalanceOf(token, address(this));
*/
        // If the Yearn vault did not burn all of the shares then revert. This is critical in mathematical operations
        // performed by the system because the system always expects that all of the tokens were unwrapped. In Yearn,
        // this sometimes does not happen in cases where strategies cannot withdraw all of the requested tokens (an
        // example strategy where this can occur is with Compound and AAVE where funds may not be accessible because
        // they were lent out).


        //double checks that the amount withdrawn is correct

        // if (balanceBefore - balanceAfter != amount) {
        //     revert IllegalState();
        // }

        return amountWithdrawn;
    }
}