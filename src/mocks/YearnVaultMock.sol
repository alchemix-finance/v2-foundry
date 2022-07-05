// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import "../libraries/TokenUtils.sol";
import "../interfaces/IERC20Minimal.sol";

contract YearnVaultMock is ERC20 {
  uint256 public constant PERCENT_RESOLUTION = 10000;
  uint256 public min = 9500;
  uint256 public constant max = 10000;

  address public token;

  uint256 public depositLimit;

  // this is for testing purposes only. not an actual part of a yearn vault
  uint256 public forcedSlippage = 0;

  constructor(address _token) ERC20("Yearn Mock", "yMOCK") {
    token = _token;
    depositLimit = type(uint256).max;
  }

  function vdecimals() external view returns (uint8) {
    return decimals();
  }

  function balance() public view returns (uint256) {
    return IERC20Minimal(token).balanceOf(address(this));
  }

  function available() public view returns (uint256) {
    return (IERC20Minimal(token).balanceOf(address(this)) * min) / max;
  }

  function deposit() external returns (uint256) {
    return deposit(type(uint256).max);
  }

  function deposit(uint256 _amount) public returns (uint256) {
    uint256 _pool = balance();
    uint256 _before = IERC20Minimal(token).balanceOf(address(this));
    // If _amount not specified, transfer the full token balance,
    // up to deposit limit
    if (_amount == type(uint256).max) {
      _amount = Math.min(depositLimit - balance(), IERC20Minimal(token).balanceOf(msg.sender));
    } else {
      require(balance() + _amount <= depositLimit, "deposit limit breached");
    }

    require(_amount > 0, "must deposit something");

    TokenUtils.safeTransferFrom(token, msg.sender, address(this), _amount);
    uint256 _after = IERC20Minimal(token).balanceOf(address(this));
    _amount = _after - _before; // Additional check for deflationary tokens
    uint256 _shares = 0;
    if (totalSupply() == 0) {
      _shares = _amount;
    } else {
      _shares = (_amount * totalSupply()) / _pool;
    }
    _mint(msg.sender, _shares);
    return _amount;
  }

  function withdraw() external returns (uint256) {
    return withdraw(balanceOf(msg.sender), msg.sender, 0);
  }

  function withdraw(uint256 _shares) external returns (uint256) {
    return withdraw(_shares, msg.sender, 0);
  }

  function withdraw(uint256 _shares, address _recipient) public returns (uint256) {
    return withdraw(_shares, _recipient, 0);
  }

  function withdraw(
    uint256 _shares,
    address _recipient,
    uint256 maxSlippage
  ) public returns (uint256) {
    // mirror real vault behavior
    if (_shares == type(uint256).max) {
      _shares = balanceOf(msg.sender);
    }
    uint256 _r = (balance() * _shares) / totalSupply();
    _burn(msg.sender, _shares);

    // apply mock slippage
    uint256 withdrawnAmt = _r - (_r * forcedSlippage) / PERCENT_RESOLUTION;
    require(withdrawnAmt >= _r - (_r * maxSlippage) / PERCENT_RESOLUTION, "too much slippage");


    TokenUtils.safeTransfer(token, _recipient, _r);
    return _r;
  }

  function pricePerShare() external view returns (uint256) {
    uint256 _totalSupply = totalSupply();
    if (_totalSupply == 0) {
      return 0;
    } else {
      return (balance() * 1e18) / totalSupply();
    }
  }

  function maxAvailableShares() external view returns (uint256) {
    return totalSupply();
  }

  function setDepositLimit(uint256 _depositLimit) external {
    depositLimit = _depositLimit;
  }

  function totalAssets() external view returns (uint256) {
    return balance();
  }

  function setForcedSlippage(uint256 _forcedSlippage) external {
    forcedSlippage = _forcedSlippage;
  }
}
