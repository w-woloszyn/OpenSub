// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "./Vm.sol";

/// @notice Minimal Test base with Foundry cheatcode handle and basic assertions.
abstract contract Test {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function fail() internal pure {
        require(false, "assertion failed");
    }

    function fail(string memory err) internal pure {
        require(false, err);
    }

    function assertTrue(bool condition) internal pure {
        if (!condition) fail();
    }

    function assertTrue(bool condition, string memory err) internal pure {
        if (!condition) fail(err);
    }

    function assertFalse(bool condition) internal pure {
        if (condition) fail();
    }

    function assertFalse(bool condition, string memory err) internal pure {
        if (condition) fail(err);
    }

    function assertEq(uint256 a, uint256 b) internal pure {
        if (a != b) fail();
    }

    function assertEq(uint256 a, uint256 b, string memory err) internal pure {
        if (a != b) fail(err);
    }

    function assertEq(address a, address b) internal pure {
        if (a != b) fail();
    }

    function assertEq(address a, address b, string memory err) internal pure {
        if (a != b) fail(err);
    }

    function assertEq(bytes32 a, bytes32 b) internal pure {
        if (a != b) fail();
    }

    function assertEq(bytes32 a, bytes32 b, string memory err) internal pure {
        if (a != b) fail(err);
    }

    function assertEq(bool a, bool b) internal pure {
        if (a != b) fail();
    }

    function assertEq(bool a, bool b, string memory err) internal pure {
        if (a != b) fail(err);
    }

    function assertGt(uint256 a, uint256 b) internal pure {
        if (a <= b) fail();
    }

    function assertGt(uint256 a, uint256 b, string memory err) internal pure {
        if (a <= b) fail(err);
    }

    function assertGe(uint256 a, uint256 b) internal pure {
        if (a < b) fail();
    }

    function assertGe(uint256 a, uint256 b, string memory err) internal pure {
        if (a < b) fail(err);
    }

    function assertLe(uint256 a, uint256 b) internal pure {
        if (a > b) fail();
    }

    function assertLe(uint256 a, uint256 b, string memory err) internal pure {
        if (a > b) fail(err);
    }
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        require(max >= min, "bound max < min");
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
}
