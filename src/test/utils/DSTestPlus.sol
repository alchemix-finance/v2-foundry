// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Test} from "../../../lib/forge-std/src/Test.sol";

import {Hevm} from "./Hevm.sol";

/// @notice Extended testing framework for DappTools projects.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/test/utils/DSTestPlus.sol)
contract DSTestPlus is Test {
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    address internal constant DEAD_ADDRESS = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

    string private checkpointLabel;
    uint256 private checkpointGasLeft;

    function startMeasuringGas(string memory label) internal virtual {
        checkpointLabel = label;
        checkpointGasLeft = gasleft();
    }

    function stopMeasuringGas() internal virtual {
        uint256 checkpointGasLeft2 = gasleft();

        string memory label = checkpointLabel;

        emit log_named_uint(string(abi.encodePacked(label, " Gas")), checkpointGasLeft - checkpointGasLeft2);
    }

    function assertUint128Eq(uint128 a, uint128 b) internal virtual {
        assertEq(uint256(a), uint256(b));
    }

    function assertUint64Eq(uint64 a, uint64 b) internal virtual {
        assertEq(uint256(a), uint256(b));
    }

    function assertUint96Eq(uint96 a, uint96 b) internal virtual {
        assertEq(uint256(a), uint256(b));
    }

    function assertUint32Eq(uint32 a, uint32 b) internal virtual {
        assertEq(uint256(a), uint256(b));
    }

    function assertBoolEq(bool a, bool b) internal virtual {
        b ? assertTrue(a) : assertFalse(a);
    }

    function assertApproxEq(
        uint256 a,
        uint256 b,
        uint256 maxDelta
    ) internal virtual {
        uint256 delta = a > b ? a - b : b - a;

        if (delta > maxDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("  Expected", a);
            emit log_named_uint("    Actual", b);
            emit log_named_uint(" Max Delta", maxDelta);
            emit log_named_uint("     Delta", delta);
            fail();
        }
    }

    function assertRelApproxEq(
        uint256 a,
        uint256 b,
        uint256 maxPercentDelta
    ) internal virtual {
        uint256 delta = a > b ? a - b : b - a;
        uint256 abs = a > b ? a : b;

        uint256 percentDelta = (delta * 1e18) / abs;

        if (percentDelta > maxPercentDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("    Expected", a);
            emit log_named_uint("      Actual", b);
            emit log_named_uint(" Max % Delta", maxPercentDelta);
            emit log_named_uint("     % Delta", percentDelta);
            fail();
        }
    }

    function assertBytesEq(bytes memory a, bytes memory b) internal virtual {
        if (keccak256(a) != keccak256(b)) {
            emit log("Error: a == b not satisfied [bytes]");
            emit log_named_bytes("  Expected", b);
            emit log_named_bytes("    Actual", a);
            fail();
        }
    }

    function assertUintArrayEq(uint256[] memory a, uint256[] memory b) internal virtual {
        require(a.length == b.length, "LENGTH_MISMATCH");

        for (uint256 i = 0; i < a.length; i++) {
            assertEq(a[i], b[i]);
        }
    }

    function expectError(string memory message) internal {
        hevm.expectRevert(bytes(message));
    }

    function expectIllegalArgumentError(string memory message) internal {
        hevm.expectRevert(abi.encodeWithSignature("IllegalArgument(string)", message));
    }

    function expectIllegalStateError(string memory message) internal {
        hevm.expectRevert(abi.encodeWithSignature("IllegalState(string)", message));
    }

    function expectUnauthorizedError(string memory message) internal {
        hevm.expectRevert(abi.encodeWithSignature("Unauthorized(string)", message));
    }

    function expectUnsupportedOperationError(string memory message) internal {
        hevm.expectRevert(abi.encodeWithSignature("UnsupportedOperation(string)", message));
    }

    function min3(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256) {
        return a > b ? (b > c ? c : b) : (a > c ? c : a);
    }

    function min2(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }
}