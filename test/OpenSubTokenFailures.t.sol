// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {OpenSub} from "src/OpenSub.sol";
import {ToggleFailERC20} from "src/mocks/ToggleFailERC20.sol";

/// @notice Encodes THREAT_MODEL.md R3: token transfer failures must not corrupt state.
contract OpenSubTokenFailuresTest is Test {
    OpenSub internal opensub;
    ToggleFailERC20 internal token;

    address internal merchant = address(0xBEEF);
    address internal subscriber = address(0xCAFE);
    address internal collector = address(0xD00D);

    uint256 internal planId;
    uint256 internal subId;

    uint256 internal constant PRICE = 10e6; // 10.000000 (6 decimals style)
    uint40 internal constant INTERVAL = 30 days;
    uint16 internal constant FEE_BPS = 500; // 5%

    function setUp() public {
        opensub = new OpenSub();
        token = new ToggleFailERC20("ToggleUSD", "tUSD", 6);

        // Fund subscriber and approve.
        token.mint(subscriber, 1_000_000_000);
        vm.prank(subscriber);
        token.approve(address(opensub), type(uint256).max);

        // Create plan.
        vm.prank(merchant);
        planId = opensub.createPlan(address(token), PRICE, INTERVAL, FEE_BPS);

        // Subscribe successfully with normal token behavior.
        vm.prank(subscriber);
        subId = opensub.subscribe(planId);
    }

    function _warpToDue() internal returns (uint40 dueAt) {
        (, , , , dueAt, ) = opensub.subscriptions(subId);
        vm.warp(dueAt);
    }

    function test_collect_reverts_and_stateUnchanged_when_transferFromReturnsFalse() public {
        uint40 dueAt = _warpToDue();

        // Snapshot state.
        (, , , , uint40 paidThroughBefore, uint40 lastChargedBefore) = opensub.subscriptions(subId);
        uint256 merchantBalBefore = token.balanceOf(merchant);
        uint256 collectorBalBefore = token.balanceOf(collector);

        // Toggle failure.
        token.setFailMode(ToggleFailERC20.FailMode.ReturnFalse);

        vm.prank(collector);
        vm.expectRevert(); // SafeERC20 should revert on false return
        opensub.collect(subId);

        // State must be unchanged.
        (, , , , uint40 paidThroughAfter, uint40 lastChargedAfter) = opensub.subscriptions(subId);
        assertEq(paidThroughAfter, paidThroughBefore);
        assertEq(lastChargedAfter, lastChargedBefore);

        assertEq(token.balanceOf(merchant), merchantBalBefore);
        assertEq(token.balanceOf(collector), collectorBalBefore);

        // Sanity: still due at the same time.
        assertTrue(block.timestamp >= uint256(dueAt));
    }

    function test_collect_reverts_and_stateUnchanged_when_transferFromReverts() public {
        _warpToDue();

        (, , , , uint40 paidThroughBefore, uint40 lastChargedBefore) = opensub.subscriptions(subId);
        uint256 merchantBalBefore = token.balanceOf(merchant);
        uint256 collectorBalBefore = token.balanceOf(collector);

        token.setFailMode(ToggleFailERC20.FailMode.Revert);

        vm.prank(collector);
        vm.expectRevert(); // token reverts
        opensub.collect(subId);

        (, , , , uint40 paidThroughAfter, uint40 lastChargedAfter) = opensub.subscriptions(subId);
        assertEq(paidThroughAfter, paidThroughBefore);
        assertEq(lastChargedAfter, lastChargedBefore);

        assertEq(token.balanceOf(merchant), merchantBalBefore);
        assertEq(token.balanceOf(collector), collectorBalBefore);
    }
}
