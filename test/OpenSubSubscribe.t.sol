// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {OpenSub} from "src/OpenSub.sol";
import {OpenSubTestBase} from "test/utils/OpenSubTestBase.sol";

contract OpenSubSubscribeTest is OpenSubTestBase {
    function test_subscribe_reverts_whenPlanPaused() public {
        uint256 planId = _createPlan(0);

        vm.prank(merchant);
        opensub.setPlanActive(planId, false);

        vm.prank(subscriber);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.PlanInactive.selector, planId));
        opensub.subscribe(planId);
    }

    function test_subscribe_chargesImmediately_setsPaidThrough_and_status() public {
        uint16 feeBps = 1234; // nonzero to ensure "fee disabled on subscribe" is meaningful
        uint256 planId = _createPlan(feeBps);

        uint40 t0 = uint40(block.timestamp);

        vm.prank(subscriber);
        uint256 subId = opensub.subscribe(planId);

        // Merchant receives full PRICE on initial charge (collector fee disabled on subscribe).
        assertEq(token.balanceOf(merchant), PRICE);

        (
            uint256 planId2,
            address subscriber2,
            OpenSub.SubscriptionStatus status,
            uint40 startTime,
            uint40 paidThrough,
            uint40 lastChargedAt
        ) = opensub.subscriptions(subId);

        assertEq(planId2, planId);
        assertEq(subscriber2, subscriber);
        assertEq(uint256(status), uint256(OpenSub.SubscriptionStatus.Active));
        assertEq(startTime, t0);
        assertEq(lastChargedAt, t0);
        assertEq(uint256(paidThrough), uint256(t0) + uint256(INTERVAL));
    }

    function test_subscribe_emits_Charged_then_Subscribed_forOpenSubLogs() public {
        uint256 planId = _createPlan(777);

        vm.recordLogs();
        vm.prank(subscriber);
        uint256 subId = opensub.subscribe(planId);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Filter to OpenSub-emitted logs only.
        bytes32 chargedSig = keccak256(
            "Charged(uint256,uint256,address,address,uint256,uint256,address,uint40,uint40)"
        );
        bytes32 subscribedSig = keccak256("Subscribed(uint256,uint256,address,uint40,uint40)");

        bytes32[] memory opensubTopics = new bytes32[](2);
        uint256 count = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(opensub)) {
                // Store the first two OpenSub events from this tx.
                if (count < 2) {
                    opensubTopics[count] = logs[i].topics[0];
                }
                count++;
            }
        }

        assertEq(count, 2, "expected exactly two OpenSub events on subscribe");
        assertEq(opensubTopics[0], chargedSig, "first OpenSub event should be Charged");
        assertEq(opensubTopics[1], subscribedSig, "second OpenSub event should be Subscribed");

        // Also sanity-check the subscription exists.
        (, address who, , , , ) = opensub.subscriptions(subId);
        assertEq(who, subscriber);
    }

    function test_subscribe_blocks_secondSubscribe_whileAccessActive() public {
        uint256 planId = _createPlan(0);
        _subscribe(planId, subscriber);

        vm.prank(subscriber);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.AlreadySubscribed.selector, planId, subscriber));
        opensub.subscribe(planId);
    }

    function test_resubscribe_allowed_afterImmediateCancel() public {
        uint256 planId = _createPlan(0);
        uint256 subId1 = _subscribe(planId, subscriber);

        vm.prank(subscriber);
        opensub.cancel(subId1, false);

        vm.prank(subscriber);
        uint256 subId2 = opensub.subscribe(planId);

        assertTrue(subId2 != subId1);
        assertEq(opensub.activeSubscriptionOf(planId, subscriber), subId2);
    }

    function test_resubscribe_blocked_duringNonRenewingAccess_thenAllowedAfterExpiry() public {
        uint256 planId = _createPlan(0);
        uint256 subId1 = _subscribe(planId, subscriber);

        (, , , , uint40 paidThrough, ) = opensub.subscriptions(subId1);

        // Schedule cancel at period end (Pattern A => NonRenewing immediately).
        vm.prank(subscriber);
        opensub.cancel(subId1, true);

        // Still blocks new subscription while access active.
        vm.warp(uint256(paidThrough) - 1);
        vm.prank(subscriber);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.AlreadySubscribed.selector, planId, subscriber));
        opensub.subscribe(planId);

        // At expiry (now == paidThrough), access is over; new subscription allowed.
        vm.warp(paidThrough);
        vm.prank(subscriber);
        uint256 subId2 = opensub.subscribe(planId);

        assertTrue(subId2 != subId1);
        assertEq(opensub.activeSubscriptionOf(planId, subscriber), subId2);
    }
}
