// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts//contracts/token/ERC20/IERC20.sol";
import {ERC20} from "../../../lib/openzeppelin-contracts//contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts//contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolService} from "../../interfaces/external/gearbox/IPoolService.sol";
import {IFarmingPool} from "../../interfaces/external/gearbox/IFarmingPool.sol";
import {IGearboxZap} from "../../interfaces/external/gearbox/IGearboxZap.sol";

contract GearboxStakingToken is ERC20 {
    using SafeERC20 for IERC20;

    IPoolService public immutable POOL_SERVICE;
    IFarmingPool public immutable FARMING_POOL;
    IGearboxZap public immutable GEARBOX_ZAP;
    IERC20 public immutable DIESEL_TOKEN;
    IERC20 public immutable UNDERLYING_TOKEN;
    IERC20 public immutable REWARD_TOKEN;

    address public admin;
    address public pendingAdmin;
    address public rewardCollector;

    constructor(
        address poolService,
        address farmingPool,
        address gearboxZap,
        address dieselToken,
        address underlyingToken,
        address rewardToken,
        address rewardCollectorAddress,
        string memory wrappedTokenName,
        string memory wrappedTokenSymbol
    ) ERC20(wrappedTokenName, wrappedTokenSymbol) {
        admin = msg.sender;
        POOL_SERVICE = IPoolService(poolService);
        FARMING_POOL = IFarmingPool(farmingPool);
        GEARBOX_ZAP = IGearboxZap(gearboxZap);
        DIESEL_TOKEN = IERC20(dieselToken);
        UNDERLYING_TOKEN = IERC20(underlyingToken);
        REWARD_TOKEN = IERC20(rewardToken);
        rewardCollector = rewardCollectorAddress;

        DIESEL_TOKEN.safeApprove(farmingPool, type(uint256).max);
        UNDERLYING_TOKEN.safeApprove(gearboxZap, type(uint256).max);
        DIESEL_TOKEN.safeApprove(gearboxZap, type(uint256).max);
    }

    function deposit(
        address recipient,
        uint256 amount,
        uint256 minLPAmount
    ) external returns (uint256) {
        return _deposit(msg.sender, recipient, amount, minLPAmount);
    }

    function withdraw(
        address recipient,
        uint256 amount,
        uint256 minAmount
    ) external returns (uint256) {
        return _withdraw(msg.sender, recipient, amount, minAmount);
    }

    function claimRewards() external returns (uint256) {
        require(msg.sender == rewardCollector, 'Not rewardCollector');
        return _claimRewards();
    }

    // ... (keep the admin functions as they were)

    function _deposit(
        address depositor,
        address recipient,
        uint256 amount,
        uint256 minLPAmount
    ) internal returns (uint256) {
        require(recipient != address(0), 'INVALID_RECIPIENT');

        UNDERLYING_TOKEN.safeTransferFrom(depositor, address(this), amount);

        uint256 receivedShares = GEARBOX_ZAP.zapIn(amount, address(this), minLPAmount);

        // Stake diesel tokens to start earning rewards
        FARMING_POOL.stake(receivedShares);

        _mint(recipient, receivedShares);
        return receivedShares;
    }

    function _withdraw(
        address owner,
        address recipient,
        uint256 amount,
        uint256 minAmount
    ) internal returns (uint256) {
        require(recipient != address(0), 'INVALID_RECIPIENT');

        _burn(owner, amount);

        // Withdraw staked diesel tokens
        FARMING_POOL.withdraw(amount);

        uint256 received = GEARBOX_ZAP.zapOut(amount, recipient, minAmount);

        return received;
    }

    function _claimRewards() internal returns (uint256) {
        FARMING_POOL.claim();

        uint256 claimed = REWARD_TOKEN.balanceOf(address(this));
        REWARD_TOKEN.safeTransfer(msg.sender, claimed);

        return claimed;
    }

    function _onlyAdmin() internal view {
        require(msg.sender == admin, "Unauthorized");
    }
}