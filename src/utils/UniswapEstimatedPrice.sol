pragma solidity ^0.8.13;

import {IUniswapV3Factory} from "../interfaces/external/uniswap/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../interfaces/external/uniswap/IUniswapV3Pool.sol";

/// @title  UniswapEstimatedPrice
/// @author Alchemix Finance
contract UniswapEstimatedPrice {
    // Set `token2` == 0 address for only one swap
    function getExpectedExchange(address factory, address token0, address token1, uint24 fee0, address token2, uint24 fee1, uint256 amount) external returns (uint256) {
        IUniswapV3Factory uniswapFactory = IUniswapV3Factory(factory);

        IUniswapV3Pool pool = IUniswapV3Pool(uniswapFactory.getPool(token0, token1, fee0));
        (uint160 sqrtPriceX96,,,,,,) =  pool.slot0();
        uint256 price0 = uint(sqrtPriceX96) * (uint(sqrtPriceX96)) * (1e18) >> (96 * 2);

        if (token2 == address(0)) return amount * price0 / 1e18;

        pool = IUniswapV3Pool(uniswapFactory.getPool(token1, token2, fee1));
        ( sqrtPriceX96,,,,,,) =  pool.slot0();
        uint256 price1 = uint(sqrtPriceX96) * (uint(sqrtPriceX96)) * (1e18) >> (96 * 2);

        return amount * price0 / price1;
    }
}