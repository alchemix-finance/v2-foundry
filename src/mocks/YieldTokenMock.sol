pragma solidity ^0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

contract YieldTokenMock is ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IERC20 public underlying;
    uint256 public totalDeposited;

    constructor(
        string memory name,
        string memory symbol,
        IERC20 _underlying
    ) ERC20(name, symbol) {
        underlying = _underlying;
    }

    function totalValue() public view returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function deposit(uint256 _amount) external {
        underlying.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 shares = 0;
        if (totalSupply() > 0) {
            shares = (_amount * totalSupply()) / totalValue();
        } else {
            shares = _amount;
        }
        _mint(msg.sender, shares);
    }

    function redeem(uint256 _amount) external {
        _burn(msg.sender, (_amount * 10**decimals()) / price());
        underlying.safeTransfer(msg.sender, _amount);
    }

    function price() public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        return (totalValue() * 10**decimals()) / totalSupply();
    }
}
