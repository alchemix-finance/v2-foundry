pragma solidity 0.8.13;

import "../../lib/ds-test/src/test.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./utils/DSTestPlus.sol";
import "../utils/CodehashWhitelist.sol";
import "./utils/mocks/ERC20Mock.sol";
import "./mocks/WhitelistedCaller.sol";
import "../interfaces/IAlchemistV2.sol";
import "./utils/Hevm.sol";
import "../../lib/forge-std/src/console.sol";

contract CodehashWhitelistTest is DSTestPlus {
    ERC20Mock token;
    CodehashWhitelist codehashWhitelist;
    WhitelistedCaller whitelistedCaller;

    // alUSD Alchemist
    IAlchemistV2 alchemist = IAlchemistV2(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd);

    // dev multisig
    address admin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address ydai = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;

    function setUp() public {
        codehashWhitelist = new CodehashWhitelist();
        whitelistedCaller = new WhitelistedCaller();
        codehashWhitelist.add(address(whitelistedCaller).codehash);
        hevm.startPrank(admin);
        alchemist.setWhitelist(address(codehashWhitelist));
        hevm.stopPrank(admin);
    }

    function testSuccessCall() public {
        uint256 amount = ERC20(dai).balanceOf(address(whitelistedCaller));
        whitelistedCaller.makeAlchemistCall(address(alchemist), ydai, amount);
        uint256 balAfter = ERC20(dai).balanceOf(address(whitelistedCaller));
    }

    function testFailCall() public {
        uint256 amount = ERC20(dai).balanceOf(address(this));
        alchemist.depositUnderlying(ydai, amount, address(this), 0);
    }

    function testRemoval() public {
        codehashWhitelist.remove(address(whitelistedCaller).codehash);
        uint256 amount = ERC20(dai).balanceOf(address(whitelistedCaller));
        expectUnauthorizedError("");
        whitelistedCaller.makeAlchemistCall(address(alchemist), ydai, amount);
    }
}