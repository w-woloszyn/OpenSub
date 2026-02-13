// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {OpenSub} from "src/OpenSub.sol";
import {OpenSubTestBase} from "test/utils/OpenSubTestBase.sol";

contract OpenSubCollectTest is OpenSubTestBase {
    function test_collect_reverts_whenNotDue() public {
        uint256 planId = _createPlan(500); // 5%
        uint256 subId = _subscribe(planId, subscriber);

        (, , , , uint40 paidThrough, ) = opensub.subscriptions(subId);

        // Still before due time.
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.NotDue.selector, paidThrough));
        opensub.collect(subId);
    }

    function test_collect_paysCollectorFee_and_merchantAmount() public {
        uint16 feeBps = 100; // 1%
        uint256 planId = _createPlan(feeBps);
        uint256 subId = _subscribe(planId, subscriber);

        uint40 dueAt = _warpToDue(subId);

        vm.prank(collector);
        (uint256 merchantAmount, uint256 collectorFee) = opensub.collect(subId);

        uint256 expectedFee = (PRICE * uint256(feeBps)) / 10_000;
        assertEq(collectorFee, expectedFee);
        assertEq(merchantAmount, PRICE - expectedFee);

        // Merchant received initial PRICE + renewal merchantAmount.
        assertEq(token.balanceOf(merchant), PRICE + merchantAmount);
        assertEq(token.balanceOf(collector), collectorFee);

        // Subscription advanced.
        (, , , , uint40 paidThroughAfter, uint40 lastChargedAtAfter) = opensub.subscriptions(subId);
        assertEq(uint256(lastChargedAtAfter), uint256(dueAt));
        assertEq(uint256(paidThroughAfter), uint256(dueAt) + uint256(INTERVAL));
    }

    function test_collect_disablesFee_whenCollectorIsSubscriber() public {
        uint16 feeBps = 1000; // 10%
        uint256 planId = _createPlan(feeBps);
        uint256 subId = _subscribe(planId, subscriber);

        _warpToDue(subId);

        uint256 merchantBalBefore = token.balanceOf(merchant);

        vm.prank(subscriber);
        (uint256 merchantAmount, uint256 collectorFee) = opensub.collect(subId);

        assertEq(collectorFee, 0);
        assertEq(merchantAmount, PRICE);

        // Merchant got full price (no collector fee).
        assertEq(token.balanceOf(merchant), merchantBalBefore + PRICE);
    }

    function test_collect_advances_paidThrough_to_now_plus_interval() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        uint40 dueAt = _warpToDue(subId);

        vm.prank(collector);
        opensub.collect(subId);

        (, , , , uint40 paidThroughAfter, uint40 lastChargedAtAfter) = opensub.subscriptions(subId);
        assertEq(uint256(lastChargedAtAfter), uint256(dueAt));
        assertEq(uint256(paidThroughAfter), uint256(dueAt) + uint256(INTERVAL));
    }

    function test_lateRenewal_restartsFromNow() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        (, , , , uint40 paidThrough, ) = opensub.subscriptions(subId);

        uint256 lateTs = uint256(paidThrough) + 7 days;
        vm.warp(lateTs);

        vm.prank(collector);
        opensub.collect(subId);

        (, , , , uint40 newPaidThrough, uint40 lastChargedAt) = opensub.subscriptions(subId);
        assertEq(uint256(lastChargedAt), lateTs);
        assertEq(uint256(newPaidThrough), lateTs + uint256(INTERVAL));
    }

    function test_collect_reverts_whenPlanPaused() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        vm.prank(merchant);
        opensub.setPlanActive(planId, false);

        _warpToDue(subId);

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.PlanInactive.selector, planId));
        opensub.collect(subId);
    }

    function test_collect_reverts_whenSubscriptionNonRenewing() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        vm.prank(subscriber);
        opensub.cancel(subId, true);

        // At/after paidThrough, it would be due if Active, but it's NonRenewing so collect must revert.
        _warpToDue(subId);

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.SubscriptionNotActive.selector, subId));
        opensub.collect(subId);
    }

    function testFuzz_collect_feeMatchesBps(uint16 feeBps) public {
        vm.assume(feeBps <= 10_000);

        uint256 planId = _createPlan(feeBps);
        uint256 subId = _subscribe(planId, subscriber);

        _warpToDue(subId);

        vm.prank(collector);
        (uint256 merchantAmount, uint256 collectorFee) = opensub.collect(subId);

        uint256 expectedFee = (PRICE * uint256(feeBps)) / 10_000;
        assertEq(collectorFee, expectedFee);
        assertEq(merchantAmount, PRICE - expectedFee);
    }
}
