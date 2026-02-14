// Auto-generated handoff ABI for viem/wagmi.
// Source: src/OpenSub.sol

import { parseAbi } from "viem";

export const openSubAbi = parseAbi([
  // Views / getters
  "function nextPlanId() view returns (uint256)",
  "function nextSubscriptionId() view returns (uint256)",
  "function plans(uint256) view returns (address merchant, address token, uint256 price, uint40 interval, uint16 collectorFeeBps, bool active, uint40 createdAt)",
  "function subscriptions(uint256) view returns (uint256 planId, address subscriber, uint8 status, uint40 startTime, uint40 paidThrough, uint40 lastChargedAt)",
  "function activeSubscriptionOf(uint256 planId, address subscriber) view returns (uint256)",
  "function computeCollectorFee(uint256 planId) view returns (uint256)",
  "function isDue(uint256 subscriptionId) view returns (bool)",
  "function hasAccess(uint256 subscriptionId) view returns (bool)",

  // Writes
  "function createPlan(address token, uint256 price, uint40 interval, uint16 collectorFeeBps) returns (uint256)",
  "function setPlanActive(uint256 planId, bool active)",
  "function subscribe(uint256 planId) returns (uint256)",
  "function cancel(uint256 subscriptionId, bool atPeriodEnd)",
  "function unscheduleCancel(uint256 subscriptionId)",
  "function collect(uint256 subscriptionId) returns (uint256 merchantAmount, uint256 collectorFee)",

  // Events
  "event PlanCreated(uint256 indexed planId, address indexed merchant, address indexed token, uint256 price, uint40 interval, uint16 collectorFeeBps)",
  "event PlanStatusChanged(uint256 indexed planId, bool active)",
  "event Subscribed(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber, uint40 startTime, uint40 paidThrough)",
  "event CancelScheduled(uint256 indexed subscriptionId, uint40 accessUntil)",
  "event CancelUnscheduled(uint256 indexed subscriptionId)",
  "event Cancelled(uint256 indexed subscriptionId, uint40 cancelledAt)",
  "event Charged(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber, address token, uint256 amount, uint256 collectorFee, address collector, uint40 chargedAt, uint40 paidThrough)",

  // Custom errors (to decode revert reasons)
  "error InvalidParameters()",
  "error InvalidPlan(uint256 planId)",
  "error PlanInactive(uint256 planId)",
  "error Unauthorized()",
  "error AlreadySubscribed(uint256 planId, address subscriber)",
  "error InvalidSubscription(uint256 subscriptionId)",
  "error NotDue(uint40 paidThrough)",
  "error SubscriptionNotActive(uint256 subscriptionId)"
] as const);
