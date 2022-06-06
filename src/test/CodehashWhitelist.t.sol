pragma solidity 0.8.13;

import "../../lib/ds-test/src/test.sol";
import "../interfaces/IERC20Metadata.sol";
import "./utils/DSTestPlus.sol";
import "../utils/CodehashWhitelist.sol";
import "./utils/mocks/ERC20Mock.sol";
import "./mocks/WhitelistedCaller.sol";
import "../interfaces/IAlchemistV2.sol";
import "../AlchemistV2.sol";
import "../interfaces/external/IProxyAdmin.sol";
import "./utils/Hevm.sol";
import "../../lib/forge-std/src/console.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";

contract CodehashWhitelistTest is DSTestPlus, stdCheats {
    ERC20Mock token;
    CodehashWhitelist codehashWhitelist;
    WhitelistedCaller whitelistedCaller;

    // alUSD Alchemist
    IAlchemistV2 alchemist = IAlchemistV2(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd);

    // dev multisig
    address admin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    IProxyAdmin proxyAdmin = IProxyAdmin(0xE0fC5CB7665041CdA26969A2D1ceb5cD5046347d);
    address ydai = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;

    function setUp() public {
        codehashWhitelist = new CodehashWhitelist();
        whitelistedCaller = new WhitelistedCaller();
        codehashWhitelist.add(address(whitelistedCaller).codehash);

        tip(ydai, address(whitelistedCaller), 1 ether);
        tip(ydai, address(this), 1 ether);

        AlchemistV2 newAlchemistLogic = new AlchemistV2();
        hevm.startPrank(admin);
        proxyAdmin.upgrade(address(alchemist), address(newAlchemistLogic));
        alchemist.setWhitelist(address(codehashWhitelist));
        hevm.stopPrank();
    }

    function testSuccessCall() public {
        uint256 amount = ERC20(ydai).balanceOf(address(whitelistedCaller));
        whitelistedCaller.makeAlchemistCall(address(alchemist), ydai, amount);
        uint256 balAfter = ERC20(ydai).balanceOf(address(whitelistedCaller));
    }

    function testFailCall() public {
        uint256 amount = ERC20(ydai).balanceOf(address(this));
        alchemist.depositUnderlying(ydai, amount, address(this), 0);
    }

    function testRemoval() public {
        codehashWhitelist.remove(address(whitelistedCaller).codehash);
        uint256 amount = ERC20(ydai).balanceOf(address(whitelistedCaller));
        expectUnauthorizedError();
        whitelistedCaller.makeAlchemistCall(address(alchemist), ydai, amount);
    }
}