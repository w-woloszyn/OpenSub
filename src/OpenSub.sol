// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title OpenSub
 * @notice Minimal, auditable on-chain subscription primitive:
 *   - Merchants create plans (token, price, interval, optional collector fee)
 *   - Users subscribe (first charge happens immediately)
 *   - Anyone can collect due payments (earns optional fee)
 *
 * Key semantics (Milestone 2):
 *   - `paidThrough` = end timestamp of the currently-paid access period.
 *   - If `status == Active`, the subscription will auto-renew when `block.timestamp >= paidThrough`.
 *   - If `status == NonRenewing`, auto-renew is disabled but access remains valid until `paidThrough`
 *     (Pattern A: no on-chain "finalize cancel" transaction is required).
 *
 * ⚠️ Not audited. Use at your own risk.
 */
contract OpenSub is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -----------------------------
    // Types
    // -----------------------------

    struct Plan {
        address merchant; // payout address (merchant)
        address token; // ERC20 to charge (e.g., USDC)
        uint256 price; // amount charged each interval (token's smallest unit)
        uint40 interval; // seconds between charges
        uint16 collectorFeeBps; // fee paid to collector, in basis points of price (0..10_000)
        bool active; // can new subs be created / charges collected?
        uint40 createdAt; // timestamp
    }

    enum SubscriptionStatus {
        None,
        Active, // auto-renew enabled
        NonRenewing, // auto-renew disabled; access valid until paidThrough
        Cancelled // ended immediately (access ended at/near cancel time)
    }

    struct Subscription {
        uint256 planId;
        address subscriber;
        SubscriptionStatus status;
        uint40 startTime; // when subscription started
        uint40 paidThrough; // end of currently-paid access period (also the next due time if Active)
        uint40 lastChargedAt; // last successful charge timestamp (0 if never)
    }

    // -----------------------------
    // Storage
    // -----------------------------

    uint256 public nextPlanId = 1;
    uint256 public nextSubscriptionId = 1;

    mapping(uint256 => Plan) public plans;
    mapping(uint256 => Subscription) public subscriptions;

    // At most one "current" subscription per (planId, subscriber) for this MVP.
    mapping(uint256 => mapping(address => uint256)) public activeSubscriptionOf;

    // -----------------------------
    // Events
    // -----------------------------

    event PlanCreated(
        uint256 indexed planId,
        address indexed merchant,
        address indexed token,
        uint256 price,
        uint40 interval,
        uint16 collectorFeeBps
    );

    event PlanStatusChanged(uint256 indexed planId, bool active);

    event Subscribed(
        uint256 indexed subscriptionId,
        uint256 indexed planId,
        address indexed subscriber,
        uint40 startTime,
        uint40 paidThrough
    );

    /// @notice Auto-renew disabled; user keeps access until `accessUntil`.
    event CancelScheduled(uint256 indexed subscriptionId, uint40 accessUntil);

    /// @notice Auto-renew re-enabled (only valid before access expires).
    event CancelUnscheduled(uint256 indexed subscriptionId);

    /// @notice Subscription ended immediately.
    event Cancelled(uint256 indexed subscriptionId, uint40 cancelledAt);

    // paid to collector (if enabled)
    // new paidThrough after this charge
    event Charged( // total charged (plan.price)
        uint256 indexed subscriptionId,
        uint256 indexed planId,
        address indexed subscriber,
        address token,
        uint256 amount,
        uint256 collectorFee,
        address collector,
        uint40 chargedAt,
        uint40 paidThrough
    );

    // -----------------------------
    // Errors
    // -----------------------------

    error InvalidParameters();
    error InvalidPlan(uint256 planId);
    error PlanInactive(uint256 planId);
    error Unauthorized();
    error AlreadySubscribed(uint256 planId, address subscriber);
    error InvalidSubscription(uint256 subscriptionId);
    error NotDue(uint40 paidThrough);
    error SubscriptionNotActive(uint256 subscriptionId);

    // -----------------------------
    // Merchant functions
    // -----------------------------

    /**
     * @notice Create a subscription plan.
     * @param token ERC20 token address to charge (e.g., USDC).
     * @param price Amount charged each interval.
     * @param interval Seconds between charges (must be > 0).
     * @param collectorFeeBps Collector fee in bps (0..10_000). This fee is taken out of `price`.
     */
    function createPlan(address token, uint256 price, uint40 interval, uint16 collectorFeeBps)
        external
        returns (uint256 planId)
    {
        if (token == address(0) || price == 0 || interval == 0) revert InvalidParameters();
        // Basic sanity: ensure token is a contract and fee math cannot overflow.
        if (token.code.length == 0) revert InvalidParameters();
        if (price > type(uint256).max / 10_000) revert InvalidParameters();
        if (collectorFeeBps > 10_000) revert InvalidParameters();

        // Minimal ERC20 shape check (prevents bricked plans from non-ERC20 contracts).
        // Note: some exotic tokens may revert here; MVP targets "normal" ERC20s like stablecoins.
        try IERC20(token).totalSupply() returns (uint256) {}
        catch {
            revert InvalidParameters();
        }

        planId = nextPlanId++;
        plans[planId] = Plan({
            merchant: msg.sender,
            token: token,
            price: price,
            interval: interval,
            collectorFeeBps: collectorFeeBps,
            active: true,
            createdAt: uint40(block.timestamp)
        });

        emit PlanCreated(planId, msg.sender, token, price, interval, collectorFeeBps);
    }

    /**
     * @notice Pause/unpause a plan. When inactive, new subscriptions cannot be created,
     *         and payments cannot be collected for existing subscriptions.
     */
    function setPlanActive(uint256 planId, bool active) external {
        Plan storage plan = plans[planId];
        if (plan.merchant == address(0)) revert InvalidPlan(planId);
        if (msg.sender != plan.merchant) revert Unauthorized();

        plan.active = active;
        emit PlanStatusChanged(planId, active);
    }

    // -----------------------------
    // Subscriber functions
    // -----------------------------

    /**
     * @notice Subscribe to a plan. Charges immediately for the first period.
     * @dev Requires the subscriber to have approved this contract for at least `plan.price`.
     *      Initial charge does NOT pay a collector fee (no third-party keeper involved).
     */
    function subscribe(uint256 planId) external nonReentrant returns (uint256 subscriptionId) {
        Plan storage plan = plans[planId];
        if (plan.merchant == address(0)) revert InvalidPlan(planId);
        if (!plan.active) revert PlanInactive(planId);

        // Enforce at most one current subscription per plan+subscriber.
        uint256 existingId = activeSubscriptionOf[planId][msg.sender];
        if (existingId != 0) {
            Subscription storage existing = subscriptions[existingId];
            if (_blocksNewSubscription(existing)) {
                revert AlreadySubscribed(planId, msg.sender);
            }
            // Stale pointer (expired / cancelled); clear it so we can create a fresh subscription.
            activeSubscriptionOf[planId][msg.sender] = 0;
        }

        subscriptionId = nextSubscriptionId++;

        uint40 nowTs = uint40(block.timestamp);

        subscriptions[subscriptionId] = Subscription({
            planId: planId,
            subscriber: msg.sender,
            status: SubscriptionStatus.Active,
            startTime: nowTs,
            paidThrough: nowTs, // due immediately; initial charge will advance by interval
            lastChargedAt: 0
        });

        activeSubscriptionOf[planId][msg.sender] = subscriptionId;

        // Initial charge at subscribe time (collector fee disabled).
        _charge(subscriptionId, address(0), false);

        emit Subscribed(subscriptionId, planId, msg.sender, nowTs, subscriptions[subscriptionId].paidThrough);
    }

    /**
     * @notice Cancel immediately (atPeriodEnd=false) or disable auto-renew while keeping access
     *         until the end of the current paid period (atPeriodEnd=true).
     *
     * Pattern A (no finalize step):
     *   - atPeriodEnd=true sets status to NonRenewing and stores access-until in `paidThrough`.
     *   - No on-chain transaction is required later to "finalize" the cancellation.
     */
    function cancel(uint256 subscriptionId, bool atPeriodEnd) external {
        Subscription storage sub = subscriptions[subscriptionId];
        if (sub.status == SubscriptionStatus.None) revert InvalidSubscription(subscriptionId);
        if (msg.sender != sub.subscriber) revert Unauthorized();
        if (sub.status == SubscriptionStatus.Cancelled) revert SubscriptionNotActive(subscriptionId);

        if (!atPeriodEnd) {
            _cancelNow(subscriptionId);
            return;
        }

        // atPeriodEnd=true
        if (sub.status == SubscriptionStatus.NonRenewing) {
            // idempotent
            return;
        }
        if (sub.status != SubscriptionStatus.Active) revert SubscriptionNotActive(subscriptionId);

        uint40 nowTs = uint40(block.timestamp);

        // If already due/overdue (no paid access remaining), treat "cancel at period end" as immediate.
        if (nowTs >= sub.paidThrough) {
            _cancelNow(subscriptionId);
            return;
        }

        sub.status = SubscriptionStatus.NonRenewing;
        emit CancelScheduled(subscriptionId, sub.paidThrough);
    }

    /**
     * @notice Re-enable auto-renew after a scheduled cancellation (only valid before access expires).
     */
    function unscheduleCancel(uint256 subscriptionId) external {
        Subscription storage sub = subscriptions[subscriptionId];
        if (sub.status == SubscriptionStatus.None) revert InvalidSubscription(subscriptionId);
        if (msg.sender != sub.subscriber) revert Unauthorized();

        if (sub.status == SubscriptionStatus.Active) return; // idempotent
        if (sub.status != SubscriptionStatus.NonRenewing) revert SubscriptionNotActive(subscriptionId);

        // Can't resume after the paid period already ended.
        if (block.timestamp >= uint256(sub.paidThrough)) revert SubscriptionNotActive(subscriptionId);

        sub.status = SubscriptionStatus.Active;
        emit CancelUnscheduled(subscriptionId);
    }

    // -----------------------------
    // Collector / Keeper function
    // -----------------------------

    /**
     * @notice Collect one due payment for a subscription.
     * @dev Anyone can call this (keeperless). Earns optional collector fee.
     */
    function collect(uint256 subscriptionId)
        external
        nonReentrant
        returns (uint256 merchantAmount, uint256 collectorFee)
    {
        (merchantAmount, collectorFee) = _charge(subscriptionId, msg.sender, true);
    }

    // -----------------------------
    // Views
    // -----------------------------

    function computeCollectorFee(uint256 planId) public view returns (uint256) {
        Plan storage plan = plans[planId];
        if (plan.merchant == address(0)) revert InvalidPlan(planId);
        return (plan.price * uint256(plan.collectorFeeBps)) / 10_000;
    }

    /// @notice True if subscription is set to auto-renew and a payment is due.
    function isDue(uint256 subscriptionId) external view returns (bool) {
        Subscription storage sub = subscriptions[subscriptionId];
        if (sub.status != SubscriptionStatus.Active) return false;
        return block.timestamp >= uint256(sub.paidThrough);
    }

    /// @notice True if subscription currently grants access (renewing or non-renewing).
    function hasAccess(uint256 subscriptionId) external view returns (bool) {
        Subscription storage sub = subscriptions[subscriptionId];
        if (sub.status == SubscriptionStatus.Active || sub.status == SubscriptionStatus.NonRenewing) {
            return block.timestamp < uint256(sub.paidThrough);
        }
        return false;
    }

    // -----------------------------
    // Internal
    // -----------------------------

    function _blocksNewSubscription(Subscription storage sub) internal view returns (bool) {
        if (sub.status == SubscriptionStatus.Active) return true;
        if (sub.status == SubscriptionStatus.NonRenewing && block.timestamp < uint256(sub.paidThrough)) return true;
        return false;
    }

    /**
     * @dev Charges the subscriber if due and advances `paidThrough`.
     *      - Uses direct transferFrom to merchant / collector (no contract custody).
     *      - "Expert" next-period logic: paidThrough becomes `max(oldPaidThrough, now) + interval`,
     *        which prevents paidThrough from remaining in the past after a successful charge.
     */
    function _charge(uint256 subscriptionId, address collector, bool allowCollectorFee)
        internal
        returns (uint256 merchantAmount, uint256 collectorFee)
    {
        Subscription storage sub = subscriptions[subscriptionId];
        if (sub.status == SubscriptionStatus.None) revert InvalidSubscription(subscriptionId);
        if (sub.status != SubscriptionStatus.Active) revert SubscriptionNotActive(subscriptionId);

        Plan storage plan = plans[sub.planId];
        if (plan.merchant == address(0)) revert InvalidPlan(sub.planId);
        if (!plan.active) revert PlanInactive(sub.planId);

        uint40 nowTs;
        uint40 newPaidThrough;

        {
            uint40 dueAt = sub.paidThrough;
            if (block.timestamp < uint256(dueAt)) revert NotDue(dueAt);

            // Best-effort mitigation: don't pay collector fees directly to the subscriber.
            // (Note: subscriber can still route collection via another address; can't be fully prevented.)
            if (collector == sub.subscriber) {
                allowCollectorFee = false;
            }

            if (allowCollectorFee && collector != address(0) && plan.collectorFeeBps != 0) {
                collectorFee = (plan.price * uint256(plan.collectorFeeBps)) / 10_000;
                if (collectorFee > plan.price) revert InvalidParameters(); // defensive
            } else {
                collectorFee = 0;
            }

            merchantAmount = plan.price - collectorFee;

            // Advance paidThrough: keep the schedule if on-time; otherwise restart from "now".
            nowTs = uint40(block.timestamp);
            uint40 base = nowTs > dueAt ? nowTs : dueAt;

            uint256 newPaidThrough256 = uint256(base) + uint256(plan.interval);
            if (newPaidThrough256 > type(uint40).max) revert InvalidParameters();
            newPaidThrough = uint40(newPaidThrough256);
        }

        // Effects (CEI): update state before transfers.
        sub.paidThrough = newPaidThrough;
        sub.lastChargedAt = nowTs;

        // Merchant payout.
        if (merchantAmount != 0) {
            IERC20(plan.token).safeTransferFrom(sub.subscriber, plan.merchant, merchantAmount);
        }

        // Collector payout (optional).
        if (collectorFee != 0) {
            IERC20(plan.token).safeTransferFrom(sub.subscriber, collector, collectorFee);
        }

        emit Charged(
            subscriptionId,
            sub.planId,
            sub.subscriber,
            plan.token,
            plan.price,
            collectorFee,
            collector,
            nowTs,
            newPaidThrough
        );
    }

    function _cancelNow(uint256 subscriptionId) internal {
        Subscription storage sub = subscriptions[subscriptionId];
        if (sub.status == SubscriptionStatus.None || sub.status == SubscriptionStatus.Cancelled) return;

        uint40 nowTs = uint40(block.timestamp);

        // End access immediately by clamping paidThrough down to now.
        if (sub.paidThrough > nowTs) {
            sub.paidThrough = nowTs;
        }

        sub.status = SubscriptionStatus.Cancelled;

        // Clear pointer if it still matches.
        uint256 current = activeSubscriptionOf[sub.planId][sub.subscriber];
        if (current == subscriptionId) {
            activeSubscriptionOf[sub.planId][sub.subscriber] = 0;
        }

        emit Cancelled(subscriptionId, nowTs);
    }
}
