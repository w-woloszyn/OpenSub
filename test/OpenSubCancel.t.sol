// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {OpenSub} from "src/OpenSub.sol";
import {OpenSubTestBase} from "test/utils/OpenSubTestBase.sol";

contract OpenSubCancelTest is OpenSubTestBase {
    function test_cancel_immediate_endsAccess_and_clearsPointer() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        // Ensure we are mid-period.
        vm.warp(block.timestamp + 3 days);

        vm.prank(subscriber);
        opensub.cancel(subId, false);

        (, , OpenSub.SubscriptionStatus status, , uint40 paidThrough, ) = opensub.subscriptions(subId);

        assertEq(uint256(status), uint256(OpenSub.SubscriptionStatus.Cancelled));
        assertEq(opensub.activeSubscriptionOf(planId, subscriber), 0);

        // Access should be gone immediately.
        assertFalse(opensub.hasAccess(subId));

        // paidThrough should be clamped to <= now
        assertLe(uint256(paidThrough), block.timestamp);
    }

    function test_cancel_atPeriodEnd_setsNonRenewing_and_keepsAccessUntilPaidThrough() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        (, , , , uint40 paidThrough, ) = opensub.subscriptions(subId);

        vm.prank(subscriber);
        opensub.cancel(subId, true);

        (, , OpenSub.SubscriptionStatus status, , , ) = opensub.subscriptions(subId);
        assertEq(uint256(status), uint256(OpenSub.SubscriptionStatus.NonRenewing));

        // Before expiry: access true
        vm.warp(uint256(paidThrough) - 1);
        assertTrue(opensub.hasAccess(subId));

        // At expiry: access false
        vm.warp(paidThrough);
        assertFalse(opensub.hasAccess(subId));

        // NonRenewing is never due (isDue returns false).
        assertFalse(opensub.isDue(subId));
    }

    function test_cancel_atPeriodEnd_whenOverdue_behavesLikeImmediateCancel() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        (, , , , uint40 paidThrough, ) = opensub.subscriptions(subId);

        // Jump to due time.
        vm.warp(paidThrough);

        vm.prank(subscriber);
        opensub.cancel(subId, true);

        (, , OpenSub.SubscriptionStatus status, , uint40 pt, ) = opensub.subscriptions(subId);
        assertEq(uint256(status), uint256(OpenSub.SubscriptionStatus.Cancelled));
        assertLe(uint256(pt), block.timestamp);
    }

    function test_unscheduleCancel_restoresActive_ifBeforeExpiry() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        (, , , , uint40 paidThrough, ) = opensub.subscriptions(subId);

        vm.prank(subscriber);
        opensub.cancel(subId, true);

        vm.warp(uint256(paidThrough) - 5);

        vm.prank(subscriber);
        opensub.unscheduleCancel(subId);

        (, , OpenSub.SubscriptionStatus status, , , ) = opensub.subscriptions(subId);
        assertEq(uint256(status), uint256(OpenSub.SubscriptionStatus.Active));
    }

    function test_unscheduleCancel_reverts_afterExpiry() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        (, , , , uint40 paidThrough, ) = opensub.subscriptions(subId);

        vm.prank(subscriber);
        opensub.cancel(subId, true);

        // Expire the access.
        vm.warp(paidThrough);

        vm.prank(subscriber);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.SubscriptionNotActive.selector, subId));
        opensub.unscheduleCancel(subId);
    }

    function test_cancel_unauthorized_reverts() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        vm.prank(stranger);
        vm.expectRevert(OpenSub.Unauthorized.selector);
        opensub.cancel(subId, false);
    }

    function test_cancel_invalidSubscription_reverts() public {
        vm.prank(subscriber);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.InvalidSubscription.selector, 999));
        opensub.cancel(999, false);
    }
}
