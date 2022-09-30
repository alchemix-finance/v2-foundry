pragma solidity ^0.8.11;

import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { Unauthorized, IllegalState, IllegalArgument } from "./base/Errors.sol";
import "./interfaces/saddle/IveSDL.sol";
import "./interfaces/stakedao/IRewardDistributor.sol";
import "./interfaces/snapshot/IDelegateRegistry.sol";
import "./interfaces/stakedao/ILiquidityGauge.sol";

contract SDLController is Initializable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  address public constant SDL = 0xf1Dc500FdE233A4055e25e5BbF516372BC4F6871;
  address public constant veSDL = 0xD2751CdBED54B87777E805be36670D7aeAe73bb2;
  string public constant version = "1.1.0";

  address public delegateRegistry;
  address public rewardDistributor;
  address public rewardToken;

  constructor() initializer {}

  function initialize() external initializer {
    __Ownable_init();
    delegateRegistry = 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;
    rewardDistributor = 0x29f3dd38dB24d3935CF1bf841e6b2B461A3E5D92;
    rewardToken = 0x3cF7b9479a01eeB3bbfC43581fa3bb21cd888e2A;
  }

  function createLock(uint256 value, uint256 lockTime) external onlyOwner {
    IERC20Upgradeable(SDL).approve(veSDL, value);
    IveSDL(veSDL).create_lock(value, lockTime);
  }

  function increaseLockAmount(uint256 value) external onlyOwner {
    IERC20Upgradeable(SDL).approve(veSDL, value);
    IveSDL(veSDL).increase_amount(value);
  }

  function increaseLockTime(uint256 lockTime) external onlyOwner {
    IveSDL(veSDL).increase_unlock_time(lockTime);
  }

  function sweep(address token, uint256 amount) external onlyOwner {
    IERC20Upgradeable(token).safeTransfer(owner(), amount);
  }

  function setDelegateRegistry(address _delegateRegistry) external onlyOwner {
    delegateRegistry = _delegateRegistry;
  }

  function setDelegate(bytes32 id, address delegate) external onlyOwner {
    IDelegateRegistry(delegateRegistry).setDelegate(id, delegate);
  }

  function clearDelegate(bytes32 id) external onlyOwner {
    IDelegateRegistry(delegateRegistry).clearDelegate(id);
  }

  function setRewardDistributor(address _rewardDistributor) external onlyOwner {
    rewardDistributor = _rewardDistributor;
  }

  function setRewardToken(address _rewardToken) external onlyOwner {
    rewardToken = _rewardToken;
  }

  function claim() external onlyOwner {
    uint256 amountClaimed = IRewardDistributor(rewardDistributor).claim();
    IERC20Upgradeable(rewardToken).safeTransfer(owner(), amountClaimed);
  }

  function claimRewards() external onlyOwner {
    ILiquidityGauge(crvRewardDistributor).claim_rewards(address(this), owner());
  }
}
