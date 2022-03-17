pragma solidity 0.8.11;

import "./interfaces/ITransmuterV1.sol";
import "./interfaces/IERC20TokenReceiver.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract TransmuterConduit {
    using SafeERC20 for IERC20;

    /// @notice Thrown when an unauthorized address attempts to access a gated function.
    error Unauthorized();

    /// @notice The address of the underlying token that is being transmuted.
    address public token;

    /// @notice The address of the transmuter to pull funds from.
    address public sourceTransmuter;

    /// @notice The address of the transmuter to send funds to;.
    address public sinkTransmuter;

    constructor(address _token, address _source, address _sink) {
        token = _token;
        sourceTransmuter = _source;
        sinkTransmuter = _sink;
    }

    function _onlySource() internal {
        if (msg.sender != sourceTransmuter) {
            revert Unauthorized();
        }
    }

    function distribute(address origin, uint256 amount) external {
        _onlySource();
        IERC20(token).safeTransferFrom(origin, sinkTransmuter, amount);
        IERC20TokenReceiver(sinkTransmuter).onERC20Received(token, amount);
    }
}