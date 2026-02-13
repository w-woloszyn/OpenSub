// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "./Test.sol";
import {Vm} from "./Vm.sol";

/// @notice Minimal StdInvariant base for Foundry invariant tests.
abstract contract StdInvariant is Test {
    function targetContract(address target) internal {
        // Best-effort call: ignore failure if cheatcode is unavailable in this forge version.
        (bool ok, ) = address(vm).call(abi.encodeWithSelector(Vm.targetContract.selector, target));
        ok;
    }
}
