pragma solidity 0.8.13;

import "./interfaces/ITransmuterV1.sol";
import "./interfaces/IERC20TokenReceiver.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./base/ErrorMessages.sol";

contract PausableTransmuterConduit {
    using SafeERC20 for IERC20;

    /// @notice The admin.
    address public admin;

    /// @notice The address of the underlying token that is being transmuted.
    address public token;

    /// @notice The address of the transmuter to pull funds from.
    address public sourceTransmuter;

    /// @notice The address of the transmuter to send funds to.
    address public sinkTransmuter;

    /// @notice Whether or not transmuter is paused.
    bool private _paused;

    constructor(address _admin, address _token, address _source, address _sink) {
        admin = _admin;
        token = _token;
        sourceTransmuter = _source;
        sinkTransmuter = _sink;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert Unauthorized("TransmuterConduit");
        }
        _;
    }

    modifier onlySource() {
        if (msg.sender != sourceTransmuter) {
            revert Unauthorized("TransmuterConduit");
        }
        _;
    }

    function distribute(address origin, uint256 amount) external onlySource() {
        if (_paused) {
            revert IllegalState("Transmuter is currently paused!");
        }
        
        IERC20(token).safeTransferFrom(origin, sinkTransmuter, amount);
        IERC20TokenReceiver(sinkTransmuter).onERC20Received(token, amount);
    }

    function pauseTransmuter(bool paused) external onlyAdmin() {
        _paused = paused;
    }
}