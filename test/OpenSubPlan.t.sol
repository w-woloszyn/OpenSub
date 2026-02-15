// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {OpenSub} from "src/OpenSub.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {OpenSubTestBase} from "test/utils/OpenSubTestBase.sol";

/// @dev A contract with code but without ERC20 totalSupply(), used to test shape-check rejection.
contract NonERC20 {
    function foo() external pure returns (uint256) {
        return 123;
    }
}

contract OpenSubPlanTest is OpenSubTestBase {
    event PlanCreated(
        uint256 indexed planId,
        address indexed merchant,
        address indexed token,
        uint256 price,
        uint40 interval,
        uint16 collectorFeeBps
    );

    function test_createPlan_storesFields_and_emitsEvent() public {
        uint16 feeBps = 250; // 2.5%

        vm.expectEmit(true, true, true, true);
        emit PlanCreated(1, merchant, address(token), PRICE, INTERVAL, feeBps);

        vm.prank(merchant);
        uint256 planId = opensub.createPlan(address(token), PRICE, INTERVAL, feeBps);

        assertEq(planId, 1);
        assertEq(opensub.nextPlanId(), 2);

        (
            address merchant_,
            address token_,
            uint256 price_,
            uint40 interval_,
            uint16 collectorFeeBps_,
            bool active_,
            uint40 createdAt_
        ) = opensub.plans(planId);

        assertEq(merchant_, merchant);
        assertEq(token_, address(token));
        assertEq(price_, PRICE);
        assertEq(interval_, INTERVAL);
        assertEq(collectorFeeBps_, feeBps);
        assertTrue(active_);
        assertEq(createdAt_, uint40(block.timestamp));
    }

    function test_createPlan_reverts_onZeroToken() public {
        vm.prank(merchant);
        vm.expectRevert(OpenSub.InvalidParameters.selector);
        opensub.createPlan(address(0), PRICE, INTERVAL, 0);
    }

    function test_createPlan_reverts_onZeroPrice() public {
        vm.prank(merchant);
        vm.expectRevert(OpenSub.InvalidParameters.selector);
        opensub.createPlan(address(token), 0, INTERVAL, 0);
    }

    function test_createPlan_reverts_onZeroInterval() public {
        vm.prank(merchant);
        vm.expectRevert(OpenSub.InvalidParameters.selector);
        opensub.createPlan(address(token), PRICE, 0, 0);
    }

    function test_createPlan_reverts_onFeeBpsTooHigh() public {
        vm.prank(merchant);
        vm.expectRevert(OpenSub.InvalidParameters.selector);
        opensub.createPlan(address(token), PRICE, INTERVAL, 10_001);
    }

    function test_createPlan_reverts_onEOAToken() public {
        address eoa = address(0x12345);
        vm.prank(merchant);
        vm.expectRevert(OpenSub.InvalidParameters.selector);
        opensub.createPlan(eoa, PRICE, INTERVAL, 0);
    }

    function test_createPlan_reverts_onNonERC20Contract() public {
        NonERC20 non = new NonERC20();
        vm.prank(merchant);
        vm.expectRevert(OpenSub.InvalidParameters.selector);
        opensub.createPlan(address(non), PRICE, INTERVAL, 0);
    }

    function test_createPlan_reverts_onPriceOverflowBound() public {
        uint256 tooBig = (type(uint256).max / 10_000) + 1;
        vm.prank(merchant);
        vm.expectRevert(OpenSub.InvalidParameters.selector);
        opensub.createPlan(address(token), tooBig, INTERVAL, 0);
    }

    function testFuzz_createPlan_acceptsValidParams(uint256 price, uint40 interval, uint16 feeBps) public {
        // Bound inputs to the contract's constraints.
        vm.assume(price > 0);
        vm.assume(interval > 0);
        vm.assume(feeBps <= 10_000);
        vm.assume(price <= type(uint256).max / 10_000);

        vm.prank(merchant);
        uint256 planId = opensub.createPlan(address(token), price, interval, feeBps);

        (
            address merchant_,
            address token_,
            uint256 price_,
            uint40 interval_,
            uint16 collectorFeeBps_,
            bool active_,
            /*createdAt*/
        ) = opensub.plans(planId);

        assertEq(merchant_, merchant);
        assertEq(token_, address(token));
        assertEq(price_, price);
        assertEq(interval_, interval);
        assertEq(collectorFeeBps_, feeBps);
        assertTrue(active_);
    }

    function test_setPlanActive_onlyMerchant() public {
        uint256 planId = _createPlan(0);

        vm.prank(stranger);
        vm.expectRevert(OpenSub.Unauthorized.selector);
        opensub.setPlanActive(planId, false);
    }

    function test_setPlanActive_reverts_onInvalidPlan() public {
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.InvalidPlan.selector, 999));
        opensub.setPlanActive(999, false);
    }

    function test_pause_blocksSubscribe_and_collect_but_cancelStillWorks() public {
        uint256 planId = _createPlan(0);
        uint256 subId = _subscribe(planId, subscriber);

        // Pause
        vm.prank(merchant);
        opensub.setPlanActive(planId, false);

        // Subscribe blocked
        vm.prank(subscriber2);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.PlanInactive.selector, planId));
        opensub.subscribe(planId);

        // Collect blocked
        uint40 dueAt = _warpToDue(subId);
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(OpenSub.PlanInactive.selector, planId));
        opensub.collect(subId);

        // But cancel should still work while paused (SPEC.md).
        vm.warp(dueAt - 1);
        vm.prank(subscriber);
        opensub.cancel(subId, false);

        (,, OpenSub.SubscriptionStatus status,,,) = opensub.subscriptions(subId);
        assertEq(uint256(status), uint256(OpenSub.SubscriptionStatus.Cancelled));
    }
}
