// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {ERC20Mock} from "./utils/mocks/ERC20Mock.sol";
import {SafeERC20User} from "./utils/users/SafeERC20User.sol";

import {IERC20Metadata} from "../interfaces/IERC20Metadata.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

/// @author Alchemix Finance
contract SafeERC20Test is DSTestPlus {
    function testExpectDecimals() external {
        ERC20Mock token = new ERC20Mock("Token", "TKN", 6);
        assertEq(SafeERC20.expectDecimals(address(token)), 6);
    }

    function testExpectDecimals(uint8 decimals) external {
        ERC20Mock token = new ERC20Mock("Token", "TKN", decimals);
        assertEq(SafeERC20.expectDecimals(address(token)), decimals);
    }

    function testFailExpectDecimalsNotPresent() external {
        NoDecimalsERC20 token = new NoDecimalsERC20();
        SafeERC20User user = new SafeERC20User(token);

        user.expectDecimals(address(token));
    }

    function testSafeApprove() external {
        ERC20Mock token = new ERC20Mock("Token", "TKN", 18);
        SafeERC20User user = new SafeERC20User(token);

        user.safeApprove(address(0xbeef), 1e18);

        assertEq(token.allowance(address(user), address(0xbeef)), 1e18);
    }

    function testSafeApproveUnsuccessful() external {
        AlwaysUnsuccessfulERC20 token = new AlwaysUnsuccessfulERC20();
        SafeERC20User user  = new SafeERC20User(token);

        expectIllegalStateError("Expected approval to succeed");
        user.safeApprove(address(0xbeef), 1e18);
    }

    function testSafeApproveReverted() external {
        AlwaysRevertERC20 token = new AlwaysRevertERC20();
        SafeERC20User user = new SafeERC20User(token);

        expectError("Approval failed");
        user.safeApprove(address(0xbeef), 1e18);
    }

    function testSafeTransfer() external {
        ERC20Mock token = new ERC20Mock("Token", "TKN", 18);
        SafeERC20User user = new SafeERC20User(token);

        token.mint(address(user), 1e18);

        user.safeTransfer(address(0xbeef), 1e18);

        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(0xbeef)), 1e18);
    }

    function testSafeTransferUnsuccessful() external {
        AlwaysUnsuccessfulERC20 token = new AlwaysUnsuccessfulERC20();
        SafeERC20User user = new SafeERC20User(token);

        expectIllegalStateError("Expected transfer to succeed");
        user.safeTransfer(address(0xbeef), 1e18);
    }

    function testSafeTransferReverted() external {
        AlwaysRevertERC20 token = new AlwaysRevertERC20();
        SafeERC20User user = new SafeERC20User(token);

        expectError("Transfer failed");
        user.safeTransfer(address(0xbeef), 1e18);
    }

    function testSafeTransferFrom() external {
        ERC20Mock token = new ERC20Mock("Token", "TKN", 18);
        SafeERC20User user = new SafeERC20User(token);

        token.mint(address(this), 1e18);
        token.approve(address(user), 1e18);

        user.safeTransferFrom(address(this), address(0xbeef), 1e18);

        assertEq(token.allowance(address(this), address(user)), 0);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0xbeef)), 1e18);
    }

    function testSafeTransferFromUnsuccessful() external {
        AlwaysUnsuccessfulERC20 token = new AlwaysUnsuccessfulERC20();
        SafeERC20User user = new SafeERC20User(token);

        expectIllegalStateError("Expected transfer from to succeed");
        user.safeTransferFrom(address(this), address(0xbeef), 1e18);
    }

    function testSafeTransferFromReverted() external {
        AlwaysRevertERC20 token = new AlwaysRevertERC20();
        SafeERC20User user = new SafeERC20User(token);

        expectError("Transfer from failed");
        user.safeTransferFrom(address(this), address(0xbeef), 1e18);
    }
}

contract AlwaysUnsuccessfulERC20 is IERC20 {
    function totalSupply() external view returns (uint256) {
        return 0;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return 0;
    }

    function balanceOf(address holder) external view returns (uint256) {
        return 0;
    }

    function approve(address spender, uint256 value) external returns (bool success) {
        return false;
    }

    function transfer(address receiver, uint256 amount) external returns (bool success) {
        return false;
    }

    function transferFrom(
        address owner,
        address receiver,
        uint256 amount
    ) external returns (bool success) {
        return false;
    }
}

contract AlwaysRevertERC20 is IERC20 {
    function totalSupply() external view returns (uint256) {
        return 0;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return 0;
    }

    function balanceOf(address holder) external view returns (uint256) {
        return 0;
    }

    function approve(address spender, uint256 value) external returns (bool success) {
        revert("Approval failed");
    }

    function transfer(address receiver, uint256 amount) external returns (bool success) {
        revert("Transfer failed");
    }

    function transferFrom(
        address owner,
        address receiver,
        uint256 amount
    ) external returns (bool success) {
        revert("Transfer from failed");
    }
}

contract NoDecimalsERC20 is IERC20 {
    function totalSupply() external view returns (uint256) {
        return 0;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return 0;
    }

    function balanceOf(address holder) external view returns (uint256) {
        return 0;
    }

    function approve(address spender, uint256 value) external returns (bool success) {
        return false;
    }

    function transfer(address receiver, uint256 amount) external returns (bool success) {
        return false;
    }

    function transferFrom(
        address owner,
        address receiver,
        uint256 amount
    ) external returns (bool success) {
        return false;
    }
}