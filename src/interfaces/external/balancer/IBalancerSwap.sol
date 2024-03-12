// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

import {IERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


enum SwapKind { GIVEN_IN, GIVEN_OUT }

struct SingleSwap {
    bytes32 poolId;
    SwapKind kind;
    IAsset assetIn;
    IAsset assetOut;
    uint256 amount;
    bytes userData;
}

struct BatchSwapStep {
    bytes32 poolId;
    uint256 assetInIndex;
    uint256 assetOutIndex;
    uint256 amount;
    bytes userData;
}

struct FundManagement {
    address sender;
    bool fromInternalBalance;
    address payable recipient;
    bool toInternalBalance;
}

interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}

interface IBalancerSwap {
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    )
    external returns (uint256);
}
