pragma solidity 0.8.13;

import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {LibCompound} from "../../libraries/LibCompound.sol";

import {ICERC20} from "../../interfaces/compound/ICERC20.sol";
import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {TokenUtils} from "../../libraries/TokenUtils.sol";
import "../../base/ErrorMessages.sol";

contract CompoundTokenAdapter is ITokenAdapter {
    /// @dev Compound error code for a noop.
    uint256 private constant NO_ERROR = 0;

    /// @dev Scalar for all fixed point numbers returned by Compound.
    uint256 private constant FIXED_POINT_SCALAR = 1e18;

    string public version = "1.0.0";
    address public alchemist;

    /// @notice An error used when a call to Compound fails.
    ///
    /// @param code The error code.
    error CompoundError(uint256 code);

    /// @inheritdoc ITokenAdapter
    address public override token;

    /// @inheritdoc ITokenAdapter
    address public override underlyingToken;

    
    uint256 public decimals;

    constructor(address _alchemist, address _token) {
        alchemist = _alchemist;
        token = _token;
        underlyingToken = ICERC20(token).underlying();
        decimals = TokenUtils.expectDecimals(underlyingToken);
    }

    /// @dev Checks that the message sender is the alchemist that the adapter is bound to.
    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert Unauthorized("Not alchemist");
        }
        _;
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        return LibCompound.viewExchangeRate(ICERC20(token)) / 10**10;
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override onlyAlchemist returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, token, amount);

        uint256 startingBalance = TokenUtils.safeBalanceOf(token, address(this));

        uint256 error;
        if ((error = ICERC20(token).mint(amount)) != NO_ERROR) {
            revert CompoundError(error);
        }

        uint256 endingBalance = TokenUtils.safeBalanceOf(token, address(this));
        uint256 mintedAmount = endingBalance - startingBalance;

        TokenUtils.safeTransfer(token, recipient, mintedAmount);

        return mintedAmount;
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override onlyAlchemist returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        uint256 startingBalance = TokenUtils.safeBalanceOf(underlyingToken, address(this));

        uint256 error;
        if ((error = ICERC20(token).redeem(amount)) != NO_ERROR) {
            revert CompoundError(error);
        }

        uint256 endingBalance = TokenUtils.safeBalanceOf(underlyingToken, address(this));
        uint256 redeemedAmount = endingBalance - startingBalance;

        TokenUtils.safeTransfer(underlyingToken, recipient, redeemedAmount);

        return redeemedAmount;
    }
}