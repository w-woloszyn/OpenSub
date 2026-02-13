// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {OpenSub} from "src/OpenSub.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

contract OpenSubSmokeTest is Test {
    OpenSub internal opensub;
    MockERC20 internal token;

    address internal merchant = address(0xBEEF);
    address internal subscriber = address(0xCAFE);
    address internal collector = address(0xD00D);

    uint256 internal planId;

    // 10.000000 tokens with 6 decimals
    uint256 internal constant PRICE = 10_000_000;
    uint40 internal constant INTERVAL = 30 days;
    uint16 internal constant FEE_BPS = 100; // 1%

    function setUp() public {
        opensub = new OpenSub();
        token = new MockERC20("MockUSD", "mUSD", 6);

        // Fund subscriber.
        token.mint(subscriber, 1_000_000_000); // 1000.000000

        vm.prank(merchant);
        planId = opensub.createPlan(address(token), PRICE, INTERVAL, FEE_BPS);

        // Approve once for all tests.
        vm.prank(subscriber);
        token.approve(address(opensub), type(uint256).max);
    }

    function _subscribe() internal returns (uint256 subId) {
        vm.prank(subscriber);
        subId = opensub.subscribe(planId);
    }

    function test_subscribe_chargesImmediately_and_setsPaidThrough() public {
        uint256 subId = _subscribe();

        // Initial charge pays merchant full price (collector fee disabled on subscribe).
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
        assertEq(lastChargedAt, startTime);
        assertGt(paidThrough, startTime);
    }

    function test_collect_paysCollector_and_advancesPaidThrough() public {
        uint256 subId = _subscribe();

        (, , , , uint40 paidThroughBefore, ) = opensub.subscriptions(subId);

        // Renew exactly when due.
        vm.warp(paidThroughBefore);

        vm.prank(collector);
        (uint256 merchantAmount, uint256 collectorFee) = opensub.collect(subId);

        uint256 expectedFee = (PRICE * uint256(FEE_BPS)) / 10_000;
        assertEq(collectorFee, expectedFee);
        assertEq(merchantAmount, PRICE - expectedFee);

        // Merchant got initial price + renewal merchant amount.
        assertEq(token.balanceOf(merchant), PRICE + merchantAmount);
        assertEq(token.balanceOf(collector), collectorFee);

        // paidThrough advanced and should be in the future relative to `block.timestamp`.
        (, , , , uint40 paidThroughAfter, ) = opensub.subscriptions(subId);
        assertGt(paidThroughAfter, uint40(block.timestamp));
    }

    function test_cancelAtPeriodEnd_patternA_disablesRenewal_but_keepsAccess() public {
        uint256 subId = _subscribe();

        (, , , , uint40 paidThrough, ) = opensub.subscriptions(subId);

        // Cancel at period end (Pattern A: set NonRenewing immediately).
        vm.prank(subscriber);
        opensub.cancel(subId, true);

        (, , OpenSub.SubscriptionStatus status, , , ) = opensub.subscriptions(subId);
        assertEq(uint256(status), uint256(OpenSub.SubscriptionStatus.NonRenewing));

        // Still has access before paidThrough.
        vm.warp(uint256(paidThrough) - 1);
        assertTrue(opensub.hasAccess(subId));

        // No access at/after paidThrough.
        vm.warp(paidThrough);
        assertFalse(opensub.hasAccess(subId));

        // collect() should revert because subscription is not Active.
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.SubscriptionNotActive.selector, subId));
        opensub.collect(subId);
    }

    function test_lateRenewal_restartsFromNow() public {
        uint256 subId = _subscribe();

        (, , , , uint40 paidThrough, ) = opensub.subscriptions(subId);

        // Warp to a time after the subscription is overdue.
        uint256 lateTs = uint256(paidThrough) + 7 days;
        vm.warp(lateTs);

        vm.prank(collector);
        opensub.collect(subId);

        (, , , , uint40 newPaidThrough, ) = opensub.subscriptions(subId);
        assertEq(uint256(newPaidThrough), lateTs + uint256(INTERVAL));
    }
}
