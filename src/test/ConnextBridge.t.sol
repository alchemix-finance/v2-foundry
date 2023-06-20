// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {TestHelper} from "../utils/TestHelper.sol";
import {ForkTestHelper} from "../utils/ForkTestHelper.sol";
import {SourceGreeterAuthenticated} from "../../greeter-authenticated/SourceGreeterAuthenticated.sol";
import {IConnext} from "@connext/interfaces/core/IConnext.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SourceGreeterAuthenticatedTestUnit
 * @notice Unit tests for SourceGreeter.
 */
contract SourceGreeterAuthenticatedTestUnit is TestHelper {
  SourceGreeterAuthenticated public source;
  address public target = address(bytes20(keccak256("Mock DestinationGreeterAuthenticated")));
  uint256 public amount = 0;
  bytes32 public transferId = keccak256("12345");
  uint256 public slippage = 0;
  address public asset = address(0);
  uint256 public relayerFee = 1e16;

  function setUp() public override {
    super.setUp();
    
    source = new SourceGreeterAuthenticated(MOCK_CONNEXT);

    vm.label(address(source), "SourceGreeterAuthenticated");
    vm.label(target, "Mock DestinationGreeterAuthenticated");
  }

  function test_SimpleBridge__updateGreeting_shouldWork(string memory newGreeting) public {
    bytes memory callData = abi.encode(newGreeting);

    // Give USER_CHAIN_A native gas to cover relayerFee
    vm.deal(USER_CHAIN_A, relayerFee);

    vm.startPrank(USER_CHAIN_A);

    // Mock the xcall
    vm.mockCall(
      MOCK_CONNEXT, 
      relayerFee,
      abi.encodeCall(
        IConnext.xcall, 
        (
          OPTIMISM_GOERLI_DOMAIN_ID,
          target,
          asset,
          USER_CHAIN_A,
          amount,
          slippage,
          callData
        )
      ),
      abi.encode(transferId)
    );

    // Test that xcall is called
    vm.expectCall(
      MOCK_CONNEXT, 
      relayerFee,
      abi.encodeCall(
        IConnext.xcall, 
        (
          OPTIMISM_GOERLI_DOMAIN_ID,
          target,
          asset,
          USER_CHAIN_A,
          amount,
          slippage,
          callData
        )
      )
    );

    source.xUpdateGreeting{value: relayerFee}(
      target,
      OPTIMISM_GOERLI_DOMAIN_ID,
      newGreeting,
      relayerFee
    );

    vm.stopPrank();
  }
}

/**
 * @title SourceGreeterAuthenticatedTestForked
 * @notice Integration tests for SourceGreeterAuthenticated. Should be run with forked testnet (Goerli).
 */
contract SourceGreeterAuthenticatedTestForked is ForkTestHelper {
  SourceGreeterAuthenticated private source;
  address public target = address(bytes20(keccak256("target")));
  uint256 public amount = 0;
  uint256 public slippage = 0;
  address public asset = address(0);
  uint256 public relayerFee = 1e16;

  function setUp() public override {
    super.setUp();

    source = new SourceGreeterAuthenticated(address(CONNEXT_GOERLI));

    vm.label(address(source), "SourceGreeterAuthenticated");
    vm.label(target, "DestinationGreeterAuthenticated");
  }

  function test_SourceGreeterAuthenticated_updateGreetingShouldWork(string memory newGreeting) public {
    // Give USER_CHAIN_A native gas to cover relayerFee
    vm.deal(USER_CHAIN_A, relayerFee);

    vm.startPrank(USER_CHAIN_A);

    // Test that xcall is called
    vm.expectCall(
      address(CONNEXT_GOERLI), 
      relayerFee,
      abi.encodeCall(
        IConnext.xcall, 
        (
          OPTIMISM_GOERLI_DOMAIN_ID,
          target,
          asset,
          USER_CHAIN_A,
          amount,
          slippage,
          abi.encode(newGreeting)
        )
      )
    );

    source.xUpdateGreeting{value: relayerFee}(
      target,
      OPTIMISM_GOERLI_DOMAIN_ID,
      newGreeting,
      relayerFee
    );
    vm.stopPrank();
  }
}