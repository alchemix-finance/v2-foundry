pragma solidity ^0.8.11;

import {IllegalState} from "../../base/Errors.sol";

import "../../interfaces/ITokenAdapter.sol";
//import some stuff for maker dai savings rate
import {IERC4626} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "../../libraries/TokenUtils.sol";

/// @title  YearnTokenAdapter
/// @author Alchemix Finance
contract DSRAdapter is ITokenAdapter {
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
        return IERC4626(token).convertToAssets(1e18);
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
        //withdraw and get the return value of underlying tokens
        uint256 amountWithdrawn = IERC4626(token).redeem(amount, recipient, address(this));

        return amountWithdrawn;
    }
}