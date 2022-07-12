// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20PermitUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

import {IllegalArgument, IllegalState} from "./base/ErrorMessages.sol";

import {TokenUtils} from "./libraries/TokenUtils.sol";

contract CrossChainCanonicalBase is ERC20PermitUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {

    // Constants for various precisions
    uint256 private constant FEE_PRECISION = 1e6; // Okay to use constant declarations since compiler does not reserve a storage slot

    /* ========== STATE VARIABLES ========== */

    // Swap fee numerators, denominator of FEE_PRECISION
    mapping(address => uint256[2]) public swapFees;
    mapping(address => bool) public feeExempt;

    // Acceptable old tokens
    address[] public bridgeTokensArray; // Used for external UIs

    // Administrative booleans
    bool public exchangesPaused; // Pause old token exchanges in case of an emergency
    mapping(address => bool) public bridgeTokenEnabled;

    /// @notice The amount that each bridge is permitted to mint.
    mapping(address => uint256) public mintCeiling;

    /// @notice The amount of tokens that each bridge has already minted.
    mapping(address => uint256) public totalMinted;

    /* ========== MODIFIERS ========== */

    modifier validBridgeToken(address tokenAddress) {
        if (!bridgeTokenEnabled[tokenAddress]) {
            revert IllegalState("Bridge token not enabled");
        }
        _;
    }

    /* ========== INITIALIZER ========== */

    function __CrossChainCanonicalBase_init(
        string memory _name,
        string memory _symbol,
        address _creatorAddress,
        address[] memory _bridgeTokens,
        uint256[] memory _mintCeilings
    ) internal {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __EIP712_init_unchained(_name, "1");
        __ERC20_init_unchained(_name, _symbol);
        __ERC20Permit_init_unchained(_name);
        __ReentrancyGuard_init_unchained(); // Note: this is called here but not in AlchemicTokenV2Base. Careful if inheriting that without this
        _transferOwnership(_creatorAddress);

        // Initialize the starting old tokens
        for (uint256 i = 0; i < _bridgeTokens.length; ++i){
            // Add to the array
            bridgeTokensArray.push(_bridgeTokens[i]);

            // Set a small swap fee initially of 0.04%
            swapFees[_bridgeTokens[i]] = [400, 400];

            // Make sure swapping is on
            bridgeTokenEnabled[_bridgeTokens[i]] = true;

            // Set mint ceiling for each bridge
            mintCeiling[_bridgeTokens[i]] = _mintCeilings[i];
        }
    }

    /* ========== VIEWS ========== */

    // Helpful for UIs
    function allBridgeTokens() external view returns (address[] memory) {
        return bridgeTokensArray;
    }

    function _isFeeExempt(address targetAddress) internal view returns (bool) {
        return feeExempt[targetAddress];
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    // Exchange old tokens for these canonical tokens
    function exchangeOldForCanonical(address bridgeTokenAddress, uint256 tokenAmount) external nonReentrant validBridgeToken(bridgeTokenAddress) returns (uint256 canonicalTokensOut) {
        if (exchangesPaused) {
            revert IllegalState("Exchanges paused");
        }

        if (!bridgeTokenEnabled[bridgeTokenAddress]) {
            revert IllegalState("Bridge token not enabled");
        }

        // Check mint caps and adjust mint count
        uint256 total = tokenAmount + totalMinted[bridgeTokenAddress];
        if (total > mintCeiling[bridgeTokenAddress]) {
            revert IllegalState();
        }
        totalMinted[bridgeTokenAddress] = total;

        // Pull in the old tokens
        TokenUtils.safeTransferFrom(bridgeTokenAddress, msg.sender, address(this), tokenAmount);

        // Handle the fee, if applicable
        canonicalTokensOut = tokenAmount;
        if (!_isFeeExempt(msg.sender)) {
            canonicalTokensOut -= ((canonicalTokensOut * swapFees[bridgeTokenAddress][0]) / FEE_PRECISION);
        }

        // Mint canonical tokens and give it to the sender
        super._mint(msg.sender, canonicalTokensOut);
    }

    // Exchange canonical tokens for old tokens
    function exchangeCanonicalForOld(address bridgeTokenAddress, uint256 tokenAmount) external nonReentrant validBridgeToken(bridgeTokenAddress) returns (uint256 bridgeTokensOut) {
        if (exchangesPaused) {
            revert IllegalState("Exchanges paused");
        }

        if (!bridgeTokenEnabled[bridgeTokenAddress]) {
            revert IllegalState("Bridge token not enabled");
        }

        // Burn the canonical tokens
        super._burn(msg.sender, tokenAmount);

        // Handle the fee, if applicable
        bridgeTokensOut = tokenAmount;
        if (!_isFeeExempt(msg.sender)) {
            bridgeTokensOut -= ((bridgeTokensOut * swapFees[bridgeTokenAddress][1]) / FEE_PRECISION);
        }

        // Update mint count
        totalMinted[bridgeTokenAddress] -= tokenAmount;

        // Give old tokens to the sender
        TokenUtils.safeTransfer(bridgeTokenAddress, msg.sender, bridgeTokensOut);
    }

    /* ========== RESTRICTED FUNCTIONS, BUT CUSTODIAN CAN CALL TOO ========== */

    function toggleExchanges() external onlyOwner {
        exchangesPaused = !exchangesPaused;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function addBridgeToken(address bridgeTokenAddress) external onlyOwner {
        // Make sure the token is not already present
        for (uint256 i = 0; i < bridgeTokensArray.length; ++i){ 
            if (bridgeTokensArray[i] == bridgeTokenAddress) {
                revert IllegalState("Token already added");
            }
        }

        // Add the old token
        bridgeTokensArray.push(bridgeTokenAddress);

        // Turn swapping on
        bridgeTokenEnabled[bridgeTokenAddress] = true;

        emit BridgeTokenAdded(bridgeTokenAddress);
    }

    function setBridgeToken(address bridgeTokenAddress, bool enabled) external onlyOwner {
        // Toggle swapping
        bridgeTokenEnabled[bridgeTokenAddress] = enabled;

        emit BridgeTokenSet(bridgeTokenAddress, enabled);
    }

    function setSwapFees(address bridgeTokenAddress, uint256 _bridgeToCanonical, uint256 _canonicalToOld) external onlyOwner {
        if(_bridgeToCanonical >= FEE_PRECISION || _canonicalToOld >= FEE_PRECISION) {
            revert IllegalArgument();
        }
        swapFees[bridgeTokenAddress] = [_bridgeToCanonical, _canonicalToOld];

        emit SwapFeeSet(bridgeTokenAddress, _bridgeToCanonical, _canonicalToOld);
    }

    /// @notice Sets the maximum amount of tokens that `minter` is allowed to mint.
    ///
    /// @notice This function reverts if `msg.sender` is not an admin.
    ///
    /// @param minter  The address of the minter.
    /// @param maximum The maximum amount of tokens that the minter is allowed to mint.
    function setCeiling(address minter, uint256 maximum) external onlyOwner {
        mintCeiling[minter] = maximum;
    }

    function toggleFeesForAddress(address targetAddress) external onlyOwner {
        feeExempt[targetAddress] = !feeExempt[targetAddress];
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        if (tokenAddress == address(this)) {
            revert IllegalArgument("Illegal token passed");
        }

        if (bridgeTokenEnabled[tokenAddress]) {
            revert IllegalState("Bridge token not enabled");
        }

        TokenUtils.safeTransfer(address(tokenAddress), msg.sender, tokenAmount);
    }

    /* ========== EVENTS ========== */

    event BridgeTokenAdded(address indexed bridgeTokenAddress);
    event BridgeTokenSet(address indexed bridgeTokenAddress, bool state);
    event SwapFeeSet(address indexed bridgeTokenAddress, uint256 bridgeToCanonical, uint256 canonicalToOld);
}