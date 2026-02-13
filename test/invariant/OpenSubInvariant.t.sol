// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import {OpenSub} from "src/OpenSub.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

/// @notice Stateful invariant tests for OpenSub (Milestone 3).
/// @dev Encodes invariants from docs/SPEC.md and risks from docs/THREAT_MODEL.md.
contract OpenSubInvariantTest is StdInvariant {
    OpenSub internal opensub;
    MockERC20 internal token;

    Handler internal handler;

    address internal merchant = address(0xBEEF);

    uint256 internal planId;

    uint256 internal constant PRICE = 10_000_000;
    uint40 internal constant INTERVAL = 30 days;
    uint16 internal constant FEE_BPS = 100; // 1%

    address[] internal subscribers;
    address[] internal collectors;

    function setUp() public {
        opensub = new OpenSub();
        token = new MockERC20("MockUSD", "mUSD", 6);

        subscribers = new address[](3);
        subscribers[0] = address(0xCAFE);
        subscribers[1] = address(0xCAFE02);
        subscribers[2] = address(0xCAFE03);

        collectors = new address[](2);
        collectors[0] = address(0xD00D);
        collectors[1] = address(0xD00E);

        // Fund + approve.
        for (uint256 i = 0; i < subscribers.length; i++) {
            token.mint(subscribers[i], 5_000_000_000); // 5000.000000
            vm.prank(subscribers[i]);
            token.approve(address(opensub), type(uint256).max);
        }

        vm.prank(merchant);
        planId = opensub.createPlan(address(token), PRICE, INTERVAL, FEE_BPS);

        handler = new Handler(opensub, token, planId, merchant, subscribers, collectors);

        targetContract(address(handler));
    }

    /// @dev SPEC.md: activeSubscriptionOf must point to the subscription matching (planId, subscriber),
    /// and should only point to Active or NonRenewing subscriptions.
    function invariant_pointerConsistency_and_status() public view {
        for (uint256 i = 0; i < subscribers.length; i++) {
            address sub = subscribers[i];
            uint256 subId = opensub.activeSubscriptionOf(planId, sub);
            if (subId == 0) continue;

            (
                uint256 planId2,
                address subscriber2,
                OpenSub.SubscriptionStatus status,
                uint40 startTime,
                uint40 paidThrough,
                uint40 lastChargedAt
            ) = opensub.subscriptions(subId);

            assertEq(planId2, planId, "pointer planId mismatch");
            assertEq(subscriber2, sub, "pointer subscriber mismatch");

            // Pointer should not point to Cancelled subscriptions (cancelNow clears it).
            assertTrue(
                status == OpenSub.SubscriptionStatus.Active || status == OpenSub.SubscriptionStatus.NonRenewing,
                "pointer points to unexpected status"
            );

            // Basic time sanity
            assertGe(lastChargedAt, startTime, "lastChargedAt < startTime");

            // SPEC.md: paidThrough is end of the paid period; contract sets paidThrough = lastChargedAt + interval.
            assertEq(uint256(paidThrough), uint256(lastChargedAt) + uint256(INTERVAL), "paidThrough invariant");

            // hasAccess must match (status in {Active, NonRenewing} && now < paidThrough)
            bool access = opensub.hasAccess(subId);
            assertEq(access, block.timestamp < uint256(paidThrough), "hasAccess mismatch");

            // isDue must match (status == Active && now >= paidThrough)
            bool due = opensub.isDue(subId);
            bool expectedDue = (status == OpenSub.SubscriptionStatus.Active) && (block.timestamp >= uint256(paidThrough));
            assertEq(due, expectedDue, "isDue mismatch");
        }
    }
}

/// @notice Handler that the invariant fuzzer calls.
/// @dev Uses best-effort guards to avoid excessive reverts.
contract Handler is Test {
    OpenSub internal opensub;
    MockERC20 internal token;

    uint256 internal planId;
    address internal merchant;

    address[] internal subscribers;
    address[] internal collectors;

    constructor(
        OpenSub opensub_,
        MockERC20 token_,
        uint256 planId_,
        address merchant_,
        address[] memory subscribers_,
        address[] memory collectors_
    ) {
        opensub = opensub_;
        token = token_;
        planId = planId_;
        merchant = merchant_;

        subscribers = subscribers_;
        collectors = collectors_;
    }

    function subscribe(uint8 subscriberIndex) external {
        address sub = subscribers[subscriberIndex % subscribers.length];

        vm.startPrank(sub);
        // ignore reverts (AlreadySubscribed, PlanInactive, etc.)
        try opensub.subscribe(planId) returns (uint256) {} catch {}
        vm.stopPrank();
    }

    function cancelImmediate(uint8 subscriberIndex) external {
        address sub = subscribers[subscriberIndex % subscribers.length];
        uint256 subId = opensub.activeSubscriptionOf(planId, sub);
        if (subId == 0) return;

        vm.prank(sub);
        try opensub.cancel(subId, false) {} catch {}
    }

    function scheduleCancel(uint8 subscriberIndex) external {
        address sub = subscribers[subscriberIndex % subscribers.length];
        uint256 subId = opensub.activeSubscriptionOf(planId, sub);
        if (subId == 0) return;

        vm.prank(sub);
        try opensub.cancel(subId, true) {} catch {}
    }

    function unschedule(uint8 subscriberIndex) external {
        address sub = subscribers[subscriberIndex % subscribers.length];
        uint256 subId = opensub.activeSubscriptionOf(planId, sub);
        if (subId == 0) return;

        vm.prank(sub);
        try opensub.unscheduleCancel(subId) {} catch {}
    }

    function collect(uint8 subscriberIndex, uint8 collectorIndex) external {
        address sub = subscribers[subscriberIndex % subscribers.length];
        uint256 subId = opensub.activeSubscriptionOf(planId, sub);
        if (subId == 0) return;

        (, , OpenSub.SubscriptionStatus status, , uint40 paidThrough, ) = opensub.subscriptions(subId);
        if (status != OpenSub.SubscriptionStatus.Active) return;
        if (block.timestamp < uint256(paidThrough)) return;

        // Skip if plan paused to avoid predictable reverts.
        (,,,,, bool active, ) = opensub.plans(planId);
        if (!active) return;

        address col = collectors[collectorIndex % collectors.length];
        vm.prank(col);
        try opensub.collect(subId) returns (uint256, uint256) {} catch {}
    }

    function setPlanActive(bool active) external {
        vm.prank(merchant);
        opensub.setPlanActive(planId, active);
    }

    function warpForward(uint32 secondsForward) external {
        // Bound the warp forward to keep invariant runs sane.
        uint256 delta = uint256(secondsForward % uint32(7 days));
        uint256 newTs = block.timestamp + delta;
        if (newTs > type(uint40).max) return;
        vm.warp(newTs);
    }

    function topUp(uint8 subscriberIndex, uint256 amount) external {
        // Allow the fuzzer to keep subscribers funded; reduces reverts from BAL/ALLOW.
        address sub = subscribers[subscriberIndex % subscribers.length];
        amount = bound(amount, 0, 1_000_000_000); // up to 1000.000000
        if (amount == 0) return;
        token.mint(sub, amount);
    }
}
