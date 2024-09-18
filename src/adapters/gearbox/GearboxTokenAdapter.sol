pragma solidity ^0.8.11;

import { IllegalState } from "../../base/Errors.sol";

import "../../libraries/TokenUtils.sol";
import { IERC4626 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import "../../interfaces/ITokenAdapter.sol";
import { IGearboxZap } from "../../interfaces/external/gearbox/IGearboxZap.sol";
import { IFarmingPool } from "../../interfaces/external/gearbox/IFarmingPool.sol";

/// @title GearboxTokenAdapter
/// @author Alchemix Finance
contract GearboxTokenAdapter is ITokenAdapter {
    uint256 private constant MAXIMUM_SLIPPAGE = 10000;
    string public constant override version = "1.0.0";

    address public immutable override token; // Gearbox Staked Diesel Token (Yield Token)
    address public immutable diesel; // Gearbox Farming Pool
    address public immutable override underlyingToken; // Underlying Token (e.g., WETH)
    address public immutable zap; // Gearbox Zap

    address public admin;
    address public rewardCollector;

    constructor(address _token, address _diesel, address _underlyingToken, address _zap) {
        token = _token;
        diesel = _diesel;
        underlyingToken = _underlyingToken;
        zap = _zap;

        admin = msg.sender;
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        // Get the price of Diesel Token in terms of the underlying token
        return IERC4626(diesel).convertToAssets(1e18);
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        // Transfer underlying tokens from msg.sender to this contract
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        // Approve the Gearbox Diesel Token contract to spend the underlying tokens
        TokenUtils.safeApprove(underlyingToken, zap, amount);

        return IGearboxZap(zap).deposit(amount, recipient);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256 amountWithdrawn) {
        // Transfer Diesel Tokens from msg.sender to this contract
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        TokenUtils.safeApprove(token, zap, amount);
        amountWithdrawn = IGearboxZap(zap).redeem(amount, recipient);
    }

    // Pass through function for harvester to claims rewards from gearbox farm.
    function claimRewards() external {
        if (msg.sender != rewardCollector && msg.sender != admin) revert("Caller is not reward collector or admin");

        IFarmingPool(token).claim();
    }

    // Admin function to sweep rewards to the collector for distribution
    function sweepRewards(address rewardToken) external returns(uint256 amount) {
        amount = TokenUtils.safeBalanceOf(rewardToken, address(this));

        if (msg.sender == rewardCollector) {
            TokenUtils.safeTransfer(rewardToken, rewardCollector, amount);
        } else if (msg.sender == admin) {
            TokenUtils.safeTransfer(rewardToken, admin, amount);
        } else revert("Not rewardCollector or admin");
    }

    // Set new reward collector address
    function setRewardCollector(address _rewardCollector) external {
        rewardCollector = _rewardCollector;
    }

    function setNewAdmin(address _admin) external {
        if (msg.sender != admin) revert("Not admin");

        admin = _admin;
    }
}