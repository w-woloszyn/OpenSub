// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {OpenSub} from "src/OpenSub.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

/// @notice Shared setup & helpers for OpenSub Milestone 3 tests.
/// @dev Encodes docs/SPEC.md assumptions (normal ERC20, 1 plan+subscriber per pointer).
abstract contract OpenSubTestBase is Test {
    OpenSub internal opensub;
    MockERC20 internal token;

    address internal merchant = address(0xBEEF);
    address internal subscriber = address(0xCAFE);
    address internal subscriber2 = address(0xCAFE02);
    address internal collector = address(0xD00D);
    address internal stranger = address(0xBAD0);

    // 10.000000 with 6 decimals (USDC-like)
    uint256 internal constant PRICE = 10_000_000;
    uint40 internal constant INTERVAL = 30 days;

    function setUp() public virtual {
        opensub = new OpenSub();
        token = new MockERC20("MockUSD", "mUSD", 6);

        // Fund subscribers generously.
        token.mint(subscriber, 1_000_000_000);  // 1000.000000
        token.mint(subscriber2, 1_000_000_000); // 1000.000000

        vm.prank(subscriber);
        token.approve(address(opensub), type(uint256).max);

        vm.prank(subscriber2);
        token.approve(address(opensub), type(uint256).max);
    }

    function _createPlan(uint16 feeBps) internal returns (uint256 planId) {
        vm.prank(merchant);
        planId = opensub.createPlan(address(token), PRICE, INTERVAL, feeBps);
    }

    function _subscribe(uint256 planId, address who) internal returns (uint256 subId) {
        vm.prank(who);
        subId = opensub.subscribe(planId);
    }

    function _warpToDue(uint256 subId) internal returns (uint40 dueAt) {
        (, , , , dueAt, ) = opensub.subscriptions(subId);
        vm.warp(dueAt);
    }
}
