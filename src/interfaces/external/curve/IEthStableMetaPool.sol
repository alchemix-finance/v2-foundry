// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

uint256 constant N_COINS = 2;

interface IEthStableMetaPool is IERC20 {
    function get_balances() external view returns (uint256[N_COINS] memory);

    function coins(uint256 index) external view returns (IERC20);

    function A() external view returns (uint256);
    
    function fee() external view returns (uint256);
    
    function totalSupply() external view returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function calc_token_amount(
        uint256[N_COINS] calldata amounts,
        bool deposit
    ) external view returns (uint256 amount);

    function add_liquidity(
        uint256[N_COINS] calldata amounts,
        uint256 minimumMintAmount
    ) external payable returns (uint256 minted);

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256 dy);

    function get_dy_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256[N_COINS] calldata balances
    ) external view returns (uint256 dy);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 minimumDy
    ) external payable returns (uint256);

    function exchange(int128 i, int128 j, uint256 dx, uint256 minimumDy, address receiver) external returns (uint256);

    function remove_liquidity(uint256 amount, uint256[N_COINS] calldata minimumAmounts) external;

    function remove_liquidity_imbalance(
        uint256[N_COINS] calldata amounts,
        uint256 maximumBurnAmount
    ) external returns (uint256);

    function calc_withdraw_one_coin(uint256 tokenAmount, int128 i) external view returns (uint256);

    function remove_liquidity_one_coin(
        uint256 tokenAmount,
        int128 i,
        uint256 minimumAmount
    ) external returns (uint256);

    function get_price_cumulative_last() external view returns (uint256[N_COINS] calldata);

    function block_timestamp_last() external view returns (uint256);

    function get_twap_balances(
        uint256[N_COINS] calldata firstBalances,
        uint256[N_COINS] calldata lastBalances,
        uint256 timeElapsed
    ) external view returns (uint256[N_COINS] calldata);

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx,
        uint256[N_COINS] calldata balances
    ) external view returns (uint256);
}