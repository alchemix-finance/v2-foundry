pragma solidity 0.8.11;

import "ds-test/test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./utils/DSTestPlus.sol";
import "../TransmuterConduit.sol";
import "./mocks/ERC20Mock.sol";
import "./mocks/TransmuterBufferMock.sol";
import "./utils/Hevm.sol";
import "forge-std/console.sol";

contract TransmuterConduitTest is DSTestPlus {
    ERC20Mock token;
    TransmuterConduit transmuterConduit;
    TransmuterBufferMock transmuterBuffer;

    address transmuterSource = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        token = new ERC20Mock("TestToken", "TEST", 18);
        transmuterBuffer = new TransmuterBufferMock(address(token));
        transmuterConduit = new TransmuterConduit(address(token), transmuterSource, address(transmuterBuffer));
        token.mint(transmuterSource, 100*10**18);
    }

    function testDistribute() public {
        uint256 amt = 10*10**18;
        hevm.startPrank(transmuterSource);
        token.approve(address(transmuterConduit), amt);
        transmuterConduit.distribute(transmuterSource, amt);
        uint256 endingBal = token.balanceOf(address(transmuterBuffer));
        console.log(endingBal);
        assertEq(endingBal, amt);
    }

    function testFailDistributeNoApproval() public {
        uint256 amt = 10*10**18;
        hevm.startPrank(transmuterSource);
        transmuterConduit.distribute(transmuterSource, amt);
    }

    function testFailDistrubteUnauthorized() public {
        address badSource = 0x0000000000000000000000000000000000000Bad;
        uint256 amt = 10*10**18;
        hevm.startPrank(badSource);
        token.approve(address(transmuterConduit), amt);
        transmuterConduit.distribute(transmuterSource, amt);
    }
}