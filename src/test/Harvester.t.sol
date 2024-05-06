// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../interfaces/IERC20TokenReceiver.sol";

import {
    WstETHAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/lido/WstETHAdapterV1.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IChainlinkOracle} from "../interfaces/external/chainlink/IChainlinkOracle.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IStableSwap2Pool} from "../interfaces/external/curve/IStableSwap2Pool.sol";
import {IStETH} from "../interfaces/external/lido/IStETH.sol";
import {IWstETH} from "../interfaces/external/lido/IWstETH.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {IResolver} from "../interfaces/keepers/IResolver.sol";
import {IAlchemixHarvester} from "../interfaces/keepers/IAlchemixHarvester.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract Harvester is DSTestPlus, IERC20TokenReceiver {
    uint256 constant BPS = 10000;
    address constant admin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant whitelistETHAddress = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;

    IAlchemistV2 constant alchemist = IAlchemistV2(0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4);
    IChainlinkOracle constant oracleStethUsd = IChainlinkOracle(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);
    IChainlinkOracle constant oracleEthUsd = IChainlinkOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    IStETH constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IStableSwap2Pool constant curvePool = IStableSwap2Pool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    WstETHAdapterV1 adapter;

    function setUp() external {

    }

    function testHarvest() external {
        // Keeper check balance of token
        (bool canExec, bytes memory execPayload) = IResolver(0x485aF43F7ED4257777A25cAB7eA3C4fa6BAa68BF).checker();

        (address alch, address yield, uint256 minOut) = abi.decode(extractCalldata(execPayload), (address, address, uint256));

        hevm.startPrank(0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a);
        alchemist.setKeeper(0x4183C9C22D1ce5F3BE9818e97e779e2897f688f7, true);
        hevm.stopPrank();
        hevm.prank(0x88Ef749aef2CB8266B2A299313881B3541432c84);
        IAlchemixHarvester(0x4183C9C22D1ce5F3BE9818e97e779e2897f688f7).harvest(alch, yield, minOut);
    }

        // For decoding bytes that have selector header
    function extractCalldata(bytes memory calldataWithSelector) internal pure returns (bytes memory) {
        bytes memory calldataWithoutSelector;

        require(calldataWithSelector.length >= 4);

        assembly {
            let totalLength := mload(calldataWithSelector)
            let targetLength := sub(totalLength, 4)
            calldataWithoutSelector := mload(0x40)
            
            mstore(calldataWithoutSelector, targetLength)

            mstore(0x40, add(0x20, targetLength))

            mstore(add(calldataWithoutSelector, 0x20), shl(0x20, mload(add(calldataWithSelector, 0x20))))

            for { let i := 0x1C } lt(i, targetLength) { i := add(i, 0x20) } {
                mstore(add(add(calldataWithoutSelector, 0x20), i), mload(add(add(calldataWithSelector, 0x20), add(i, 0x04))))
            }
        }

        return calldataWithoutSelector;
    }

    function onERC20Received(address token, uint256 value) external {
        return;
    }
}