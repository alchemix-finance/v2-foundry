pragma solidity ^0.8.11;

import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { Unauthorized, IllegalState, IllegalArgument } from "./base/Errors.sol";
import "./interfaces/stakedao/IveSDT.sol";
import "./interfaces/stakedao/IRewardDistributor.sol";
import "./interfaces/snapshot/IDelegateRegistry.sol";
import "./interfaces/stakedao/ILiquidityGauge.sol";
import "./interfaces/stakedao/IGaugeController.sol";
import "./interfaces/stakedao/IGauge.sol";

contract SDTController is Initializable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  address public constant SDT = 0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F;
  address public constant veSDT = 0x0C30476f66034E11782938DF8e4384970B6c9e8a;
  string public constant version = "1.2.0";

  address public delegateRegistry;
  address public rewardDistributor;
  address public rewardToken;
  address public crvRewardDistributor;
  address public gaugeController;

  constructor() initializer {}

  function initialize() external initializer {
    __Ownable_init();
    delegateRegistry = 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;
    rewardDistributor = 0x29f3dd38dB24d3935CF1bf841e6b2B461A3E5D92;
    rewardToken = 0x5af15DA84A4a6EDf2d9FA6720De921E1026E37b7;
    gaugeController = 0x75f8f7fa4b6DA6De9F4fE972c811b778cefce882;
  }

  function createLock(uint256 value, uint256 lockTime) external onlyOwner {
    IERC20Upgradeable(SDT).approve(veSDT, value);
    IveSDT(veSDT).create_lock(value, lockTime);
  }

  function increaseLockAmount(uint256 value) external onlyOwner {
    IERC20Upgradeable(SDT).approve(veSDT, value);
    IveSDT(veSDT).increase_amount(value);
  }

  function increaseLockTime(uint256 lockTime) external onlyOwner {
    IveSDT(veSDT).increase_unlock_time(lockTime);
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

  function setGaugeController(address _gaugeController) external onlyOwner {
    gaugeController = _gaugeController;
  }

  function claim() external onlyOwner {
    uint256 amountClaimed = IRewardDistributor(rewardDistributor).claim();
    IERC20Upgradeable(rewardToken).safeTransfer(owner(), amountClaimed);
  }

  function voteForGaugeWeights(address controller, address gaugeAddress, uint256 weight) external onlyOwner {
    IGaugeController(controller).vote_for_gauge_weights(gaugeAddress, weight);
  }

  function setCrvRewardDistributor(address _crvRewardDistributor) external onlyOwner {
    crvRewardDistributor = _crvRewardDistributor;
  }

  function claimRewards() external onlyOwner {
    ILiquidityGauge(crvRewardDistributor).claim_rewards(address(this), owner());
  }

  function userCheckpoint(address gaugeAddress) external onlyOwner returns (bool) {
   return IGauge(gaugeAddress).user_checkpoint(address(this));
  }
}
