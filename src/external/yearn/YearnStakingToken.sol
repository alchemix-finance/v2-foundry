// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import {IStakingRewards} from '../../interfaces/external/yearn/IStakingRewards.sol';
import {IYearnVaultV2} from '../../interfaces/external/yearn/IYearnVaultV2.sol';
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenUtils} from "../../libraries/TokenUtils.sol";

import {Unauthorized, IllegalState, IllegalArgument} from "../../base/Errors.sol";

/// @title YearnStakingToken
///
/// @dev Wrapper token that allows staking on yearn to receive OP rewards.
/// Intended for optimism network.
///
/// @author Alchemix Finance
contract YearnStakingToken is ERC20 {
    using SafeERC20 for IERC20;

    IStakingRewards public immutable STAKNG_REWARDS;
    IYearnVaultV2 public immutable YEARN_VAULT;
    IERC20 public immutable ASSET;
    IERC20 public immutable REWARD;

    address public admin;
    address public pendingAdmin;
    address public rewardCollector;

    uint8 private _decimals;

    constructor(
        address stakingRewards,
        address yToken,
        address underlyingToken,
        address rewardToken,
        address _rewardCollector,
        string memory wrappedTokenName,
        string memory wrappedTokenSymbol
    ) ERC20(wrappedTokenName, wrappedTokenSymbol) {
        admin = msg.sender;
        STAKNG_REWARDS = IStakingRewards(stakingRewards);
        YEARN_VAULT = IYearnVaultV2(yToken);

        ASSET = IERC20(underlyingToken);
        REWARD = IERC20(rewardToken);

        rewardCollector = _rewardCollector;

        TokenUtils.safeApprove(underlyingToken, yToken, type(uint256).max);
        TokenUtils.safeApprove(yToken, address(stakingRewards), type(uint256).max);
        _decimals = IERC20Metadata(yToken).decimals();
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @dev Deposits `ASSET` in the Yearn protocol and mints wrapper tokens to msg.sender
    ///
    /// @param  recipient The address that will receive the wrapper tokens
    /// @param  amount    The amount of underlying `ASSET` to deposit (e.g. deposit of 100 USDC)
    ///
    /// @return uint256   The amount of wrapper tokens minted
    function deposit(
        address recipient,
        uint256 amount
    ) external returns (uint256) {
        return _deposit(msg.sender, recipient, amount);
    }


    /// @dev Burns `amount` of wrappet Token, with recipient receiving the corresponding amount of `ASSET`
    ///
    /// @param  recipient         The address that will receive the amount of `ASSET` withdrawn from the Yearn protocol
    /// @param  amount            The amount to withdraw in shares
    ///
    /// @return amountToBurn      Wrapper tokens burned
    /// @return amountToWithdraw  underlying tokens withdrawn
    function withdraw(
        address recipient,
        uint256 amount,
        uint256 maxSlippage
    ) external returns (uint256, uint256) {
        return _withdraw(msg.sender, recipient, amount, maxSlippage);
    }

    /// @dev Burns `amount` of wrapper token, with recipient receiving the corresponding amount of `ASSET`
    ///
    /// @return claimed  Amount of rewards claimed
    function claimRewards() external returns (uint256) {
        require(msg.sender == rewardCollector, 'Not rewardCollector');
        return _claimRewards();
    }

    function setRewardCollector(address _rewardCollector) external {
        _onlyAdmin();
        rewardCollector = _rewardCollector;
    }

    function setPendingAdmin(address newAdmin) external {
        _onlyAdmin();
        require(newAdmin != address(0), "0 address");
        pendingAdmin = newAdmin;
    }

    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "must be pending admin");
        admin = pendingAdmin;
    }

    function _deposit(
        address depositor,
        address recipient,
        uint256 amount
    ) internal returns (uint256) {
        require(recipient != address(0), 'INVALID_RECIPIENT');
        
        ASSET.safeTransferFrom(depositor, address(this), amount);

        // Deposit into yearn vault.
        uint256 receivedShares = YEARN_VAULT.deposit(amount, address(this));

        // Stake yTokens to start earning OP.
        STAKNG_REWARDS.stake(receivedShares);

        _mint(recipient, receivedShares);
        return receivedShares;
    }

    function _withdraw(
        address owner,
        address recipient,
        uint256 amount,
        uint256 maxSlippage
    ) internal returns (uint256, uint256) {
        require(recipient != address(0), 'INVALID_RECIPIENT');

        _burn(owner, amount);

        // Withdraw staked yTokens.
        STAKNG_REWARDS.withdraw(amount);
        
        // Withdraw collateral.
        uint256 received = YEARN_VAULT.withdraw(amount, recipient, maxSlippage);

        return (amount, received);
    }

    function _claimRewards() internal returns (uint256) {
        STAKNG_REWARDS.getReward();

        uint256 claimed = IERC20(REWARD).balanceOf(address(this));

        SafeERC20.safeTransfer(REWARD, msg.sender, claimed);

        return claimed;
    }

    /// @dev Checks that the `msg.sender` is the administrator.
    ///
    /// @dev `msg.sender` must be the administrator or this call will revert with an {Unauthorized} error.
    function _onlyAdmin() internal view {
        if (msg.sender != admin) {
            revert Unauthorized();
        }
    }
}