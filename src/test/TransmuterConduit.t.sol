pragma solidity 0.8.13;

import "../../lib/ds-test/src/test.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./utils/DSTestPlus.sol";
import "../TransmuterConduit.sol";
import "./utils/mocks/ERC20MockDecimals.sol";
import "./mocks/TransmuterBufferMock.sol";
import "./utils/Hevm.sol";
import "../../lib/forge-std/src/console.sol";

contract TransmuterConduitTest is DSTestPlus {
    ERC20MockDecimals token;
    TransmuterConduit transmuterConduit;
    TransmuterBufferMock transmuterBuffer;

    address transmuterSource = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        token = new ERC20MockDecimals("TestToken", "TEST", 18);
        transmuterBuffer = new TransmuterBufferMock(address(token));
        transmuterConduit = new TransmuterConduit(address(token), transmuterSource, address(transmuterBuffer));
        token.mint(transmuterSource, 100*10e18);
    }

    function testDistribute() public {
        uint256 amount = 10*10e18;
        hevm.startPrank(transmuterSource);
        token.approve(address(transmuterConduit), amount);
        transmuterConduit.distribute(transmuterSource, amount);
        uint256 endingBal = token.balanceOf(address(transmuterBuffer));
        console.log(endingBal);
        assertEq(endingBal, amount);
    }

    function testFailDistributeNoApproval() public {
        uint256 amount = 10*10e18;
        hevm.startPrank(transmuterSource);
        transmuterConduit.distribute(transmuterSource, amount);
    }

    function testFailDistrubteUnauthorized() public {
        address badSource = 0x0000000000000000000000000000000000000Bad;
        uint256 amount = 10*10e18;
        hevm.startPrank(badSource);
        token.approve(address(transmuterConduit), amount);
        transmuterConduit.distribute(transmuterSource, amount);
    }
}