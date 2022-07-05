pragma solidity ^0.8.11;

import "../../interfaces/IERC3156FlashLender.sol";
import "../../interfaces/IERC3156FlashBorrower.sol";
import "../../interfaces/IERC20Minimal.sol";

contract TestFlashBorrower {
  bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

  constructor() {}

  function takeLoan(
    address flashLender,
    address token,
    uint256 amount
  ) external {
    uint256 fee = IERC3156FlashLender(flashLender).flashFee(flashLender, amount);
    IERC20Minimal(token).approve(flashLender, amount + fee);
    IERC3156FlashLender(flashLender).flashLoan(IERC3156FlashBorrower(address(this)), token, amount, bytes(""));
  }

  function onFlashLoan(
    address from,
    address token,
    uint256 amount,
    uint256 fee,
    bytes calldata data
  ) external returns (bytes32) {
    return CALLBACK_SUCCESS;
  }
}
