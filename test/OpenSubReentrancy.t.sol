// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {OpenSub} from "src/OpenSub.sol";
import {ReentrantERC20} from "src/mocks/ReentrantERC20.sol";

/// @notice Encodes THREAT_MODEL.md R1: reentrancy during token transfers must not allow re-entry.
contract OpenSubReentrancyTest is Test {
    OpenSub internal opensub;
    ReentrantERC20 internal token;

    address internal merchant = address(0xBEEF);
    address internal subscriber = address(0xCAFE);

    uint256 internal planId;

    uint256 internal constant PRICE = 10_000_000;
    uint40 internal constant INTERVAL = 30 days;

    function setUp() public {
        opensub = new OpenSub();
        token = new ReentrantERC20("ReentryUSD", "rUSD", 6);

        // Fund and approve.
        token.mint(subscriber, 1_000_000_000);

        vm.prank(subscriber);
        token.approve(address(opensub), type(uint256).max);

        // Create plan.
        vm.prank(merchant);
        planId = opensub.createPlan(address(token), PRICE, INTERVAL, 0);

        // Configure token to attempt reentry into this OpenSub plan/subscriber combo.
        token.setReentryConfig(address(opensub), planId, subscriber);
    }

    function test_subscribe_succeeds_and_reentrancyAttemptFails() public {
        // Subscribe should succeed; token will attempt to call OpenSub.collect() during transferFrom.
        vm.prank(subscriber);
        uint256 subId = opensub.subscribe(planId);

        // Merchant should have received initial payment.
        // (Reentrant token behaves normally for the transfer itself.)
        // Note: this assumes no collector fee on subscribe (SPEC.md).
        assertEq(token.balanceOf(merchant), PRICE);

        assertTrue(token.reentryAttempted(), "expected reentry attempted during transferFrom");
        assertFalse(token.reentrySucceeded(), "reentry should not succeed (nonReentrant)");

        // Subscription exists.
        (, address who, , , , ) = opensub.subscriptions(subId);
        assertEq(who, subscriber);
    }
}
