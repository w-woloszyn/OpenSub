import { parseAbiItem } from "viem";

// Keep event definitions centralized so a non-blockchain frontend dev can see
// what the protocol emits without reading Solidity.

export const OpenSubEvents = {
  PlanCreated: parseAbiItem(
    "event PlanCreated(uint256 indexed planId, address indexed merchant, address indexed token, uint256 price, uint40 interval, uint16 collectorFeeBps)"
  ),
  PlanStatusChanged: parseAbiItem(
    "event PlanStatusChanged(uint256 indexed planId, bool active)"
  ),
  Subscribed: parseAbiItem(
    "event Subscribed(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber, uint40 startTime, uint40 paidThrough)"
  ),
  CancelScheduled: parseAbiItem(
    "event CancelScheduled(uint256 indexed subscriptionId, uint40 accessUntil)"
  ),
  CancelUnscheduled: parseAbiItem(
    "event CancelUnscheduled(uint256 indexed subscriptionId)"
  ),
  Cancelled: parseAbiItem(
    "event Cancelled(uint256 indexed subscriptionId, uint40 cancelledAt)"
  ),
  Charged: parseAbiItem(
    "event Charged(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber, address token, uint256 amount, uint256 collectorFee, address collector, uint40 chargedAt, uint40 paidThrough)"
  ),
} as const;

export const OpenSubEventList = Object.values(OpenSubEvents);
