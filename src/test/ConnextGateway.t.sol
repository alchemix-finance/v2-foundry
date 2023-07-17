pragma solidity ^0.8.13;

import {console} from "../../lib/forge-std/src/console.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {Hevm} from "./utils/Hevm.sol";
 
import {AlchemixConnextGateway} from "../bridging/connext/AlchemixConnextGateway.sol";

import "../libraries/TokenUtils.sol";


contract ConnextGateway is DSTestPlus {

    AlchemixConnextGateway gateway;
    function setUp() public {
        gateway = new AlchemixConnextGateway(0x8f7492DE823025b4CfaAB1D34c58963F2af5DEDA);
        gateway.registerAsset(0x49000f5e208349D2fA678263418e21365208E498, 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A);
        deal(0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A, address(this), 10e18);
        deal(0x49000f5e208349D2fA678263418e21365208E498, address(gateway), 100e18);

    }

    function testBridge() external {
        TokenUtils.safeApprove(0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A, address(gateway), 100e18);
        gateway.bridgeAssets(address(this), 0x49000f5e208349D2fA678263418e21365208E498, 1e18, 6648936, 0);
    }

    function testReceive() external {
        hevm.prank(0x8f7492DE823025b4CfaAB1D34c58963F2af5DEDA);
        gateway.xReceive(bytes32("0"), 1e18, 0x49000f5e208349D2fA678263418e21365208E498, 0x8f7492DE823025b4CfaAB1D34c58963F2af5DEDA, 0, abi.encode(address(this)));
    }
}