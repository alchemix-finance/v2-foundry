pragma solidity ^0.8.11;

import "../../interfaces/ITokenAdapter.sol";
import "../../interfaces/external/idle/IIdleCDO.sol";

import "../../libraries/TokenUtils.sol";

/// @title  Idle PYT Adapter
/// @author Idle Finance
contract IdleTrancheAdapter is ITokenAdapter {
    string public constant override version = "1.0.0";

    address public immutable override token;
    address public immutable override underlyingToken;
    IIdleCDO public immutable idleCDO;
    bool public immutable isAATranche;

    constructor(address _token, address _underlyingToken, address _idleCDO) {
        token = _token;
        underlyingToken = _underlyingToken;
        idleCDO = IIdleCDO(_idleCDO);
        isAATranche = _token == IIdleCDO(_idleCDO).AATranche();
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        return idleCDO.virtualPrice(token);
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, address(idleCDO), 0);
        TokenUtils.safeApprove(underlyingToken, address(idleCDO), amount);

        uint256 mintedTranche = isAATranche ? idleCDO.depositAA(amount) : idleCDO.depositBB(amount);

        TokenUtils.safeTransfer(token, recipient, mintedTranche);
        return mintedTranche;
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        uint256 balanceBefore = TokenUtils.safeBalanceOf(underlyingToken, address(this));
        isAATranche ? idleCDO.withdrawAA(amount) : idleCDO.withdrawBB(amount);
        uint256 amountWithdrawn = TokenUtils.safeBalanceOf(underlyingToken, address(this)) - balanceBefore;

        TokenUtils.safeTransfer(underlyingToken, recipient, amountWithdrawn);
        return amountWithdrawn;
    }
}
