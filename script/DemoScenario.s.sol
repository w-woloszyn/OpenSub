// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {OpenSub} from "src/OpenSub.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

/**
 * DemoScenario
 *
 * A "seed the chain" script for frontend devs.
 *
 * Deploys:
 *  - MockERC20 (mUSDC)
 *  - OpenSub
 *  - A demo plan
 *
 * Optionally (if SUBSCRIBER or SUBSCRIBER_PK is provided):
 *  - mints tokens to subscriber
 *  - approves allowance
 *  - subscribes (emits Subscribed + Charged)
 *  - on local Anvil, can also advance time + renew (emits another Charged)
 */
contract DemoScenario is Script {
    // Token defaults
    uint8 internal constant TOKEN_DECIMALS = 6;

    // Plan defaults (override via env)
    uint256 internal constant PLAN_PRICE_DEFAULT = 10_000_000; // 10.000000
    uint40 internal constant PLAN_INTERVAL_DEFAULT = 30 days;
    uint16 internal constant PLAN_COLLECTOR_FEE_BPS_DEFAULT = 100; // 1%

    // Mint defaults (override via env)
    uint256 internal constant MINT_TO_MERCHANT_DEFAULT = 10_000 * 10 ** uint256(TOKEN_DECIMALS);
    uint256 internal constant MINT_TO_SUBSCRIBER_DEFAULT = 100 * 10 ** uint256(TOKEN_DECIMALS);

    // Allowance policy default
    uint256 internal constant APPROVAL_PERIODS_DEFAULT = 12;

    function run() external {
        console2.log("=== DemoScenario ===");
        console2.log("chainid:", vm.toString(block.chainid));

        uint256 planPrice = _envOrUint("PLAN_PRICE", PLAN_PRICE_DEFAULT);
        uint40 planInterval = uint40(_envOrUint("PLAN_INTERVAL_SECONDS", uint256(PLAN_INTERVAL_DEFAULT)));
        uint16 planFeeBps = uint16(_envOrUint("PLAN_COLLECTOR_FEE_BPS", uint256(PLAN_COLLECTOR_FEE_BPS_DEFAULT)));

        uint256 mintToMerchant = _envOrUint("MINT_TO_MERCHANT", MINT_TO_MERCHANT_DEFAULT);
        uint256 mintToSubscriber = _envOrUint("MINT_TO_SUBSCRIBER", MINT_TO_SUBSCRIBER_DEFAULT);

        uint256 approvalPeriods = _envOrUint("APPROVAL_PERIODS", APPROVAL_PERIODS_DEFAULT);
        if (approvalPeriods == 0) approvalPeriods = 1;

        // Resolve subscriber
        address subscriber = _readOptionalAddress("SUBSCRIBER");
        uint256 subscriberPk = 0;
        if (subscriber == address(0)) {
            subscriberPk = _readOptionalUint("SUBSCRIBER_PK");
            if (subscriberPk != 0) {
                subscriber = vm.addr(subscriberPk);
            }
        }

        // 1) Deploy contracts
        vm.startBroadcast();
        MockERC20 token = new MockERC20("Mock USD Coin", "mUSDC", TOKEN_DECIMALS);
        OpenSub opensub = new OpenSub();
        vm.stopBroadcast();

        uint256 tokenDeployBlock = block.number;
        uint256 openSubDeployBlock = block.number;

        // 2) Create plan from merchant (broadcaster)
        vm.startBroadcast();
        uint256 planId = opensub.createPlan(address(token), planPrice, planInterval, planFeeBps);
        vm.stopBroadcast();

        (address merchant,,,,,,) = opensub.plans(planId);

        // 3) Mint demo funds
        vm.startBroadcast();
        token.mint(merchant, mintToMerchant);
        vm.stopBroadcast();

        if (subscriber != address(0)) {
            vm.startBroadcast();
            token.mint(subscriber, mintToSubscriber);
            vm.stopBroadcast();
        }

        console2.log("\n--- Deployed ---");
        console2.log("Token (mUSDC):", address(token));
        console2.log("OpenSub:", address(opensub));
        console2.log("Token deploy block (lower bound):", tokenDeployBlock);
        console2.log("OpenSub deploy block (lower bound):", openSubDeployBlock);
        console2.log("PlanId:", planId);
        console2.log("Plan price:", planPrice);
        console2.log("Plan interval (seconds):", uint256(planInterval));
        console2.log("Plan collector fee (bps):", uint256(planFeeBps));
        console2.log("Merchant:", merchant);

        if (subscriber != address(0)) {
            console2.log("Subscriber:", subscriber);
        } else {
            console2.log("Subscriber: (not provided; set SUBSCRIBER or SUBSCRIBER_PK to run approve+subscribe)");
        }

        _printPasteReadyFrontendConfig(address(opensub), openSubDeployBlock, address(token), tokenDeployBlock, TOKEN_DECIMALS, planId);

        // 4) Optionally approve + subscribe
        if (subscriberPk == 0) {
            console2.log("\nNOTE: SUBSCRIBER_PK not set; skipping approve+subscribe step.");
            console2.log("To seed a subscription, export SUBSCRIBER_PK=<pk> (funded with gas).\n");
            return;
        }

        uint256 approveAmount = planPrice * approvalPeriods;
        console2.log("\n--- Subscriber approve + subscribe ---");
        console2.log("Approval periods:", approvalPeriods);
        console2.log("Approve amount:", approveAmount);

        vm.startBroadcast(subscriberPk);
        token.approve(address(opensub), approveAmount);
        uint256 subId = opensub.subscribe(planId);
        vm.stopBroadcast();

        console2.log("Subscribed. subscriptionId:", subId);

        // 5) Optionally renew on Anvil (requires FFI to call cast rpc)
        bool doRenewal = _readOptionalBool("DO_RENEWAL", false);
        bool useFfi = _readOptionalBool("USE_FFI", false);

        if (doRenewal) {
            if (block.chainid != 31337) {
                console2.log("NOTE: Renewal requested but not on local Anvil; skipping (cannot warp time on public networks).\n");
                return;
            }
            if (!useFfi) {
                console2.log("NOTE: renewal is enabled but USE_FFI is not set.");
                console2.log("Set USE_FFI=1 and run with --ffi to allow time travel on Anvil.\n");
                return;
            }

            // Determine when due
            (, , , , uint40 paidThrough, ) = opensub.subscriptions(subId);
            uint256 nowTs = block.timestamp;
            if (nowTs < uint256(paidThrough)) {
                uint256 secondsForward = uint256(paidThrough) - nowTs;
                console2.log("Advancing time by seconds:", secondsForward);
                _ffiIncreaseTime(secondsForward);
                _ffiMine();
            }

            console2.log("Calling collect() to renew...");
            vm.startBroadcast(subscriberPk);
            opensub.collect(subId);
            vm.stopBroadcast();

            console2.log("Renewal complete.\n");
        }

        console2.log("Done.");
    }

    function _printPasteReadyFrontendConfig(
        address openSub,
        uint256 openSubDeployBlock,
        address token,
        uint256 /*tokenDeployBlock*/,
        uint8 tokenDecimals,
        uint256 planId
    ) internal view {
        (string memory key, string memory name) = _configKeyAndName();

        uint256 fromBlock = openSubDeployBlock;
        if (block.chainid != 31337) {
            uint256 buffer = 2_000;
            fromBlock = openSubDeployBlock > buffer ? openSubDeployBlock - buffer : 0;
        }

        console2.log("\n=== Paste-ready config snippets ===\n");

        console2.log("// frontend/config/addresses.ts");
        console2.log("export const addresses = {");
        console2.log(string.concat("  ", key, ": {"));
        console2.log(string.concat("    chainName: \"", name, "\","));
        console2.log(string.concat("    openSub: \"", vm.toString(openSub), "\","));
        console2.log(string.concat("    deployBlock: ", vm.toString(fromBlock), "n,"));
        console2.log("  },");
        console2.log("} as const;\n");

        console2.log("// frontend/config/tokens.ts");
        console2.log("export const tokens = {");
        console2.log(string.concat("  ", key, ": ["));
        console2.log("    {");
        console2.log(string.concat("      symbol: \"mUSDC\","));
        console2.log(string.concat("      name: \"Mock USD Coin\","));
        console2.log(string.concat("      address: \"", vm.toString(token), "\","));
        console2.log(string.concat("      decimals: ", vm.toString(uint256(tokenDecimals)), ","));
        console2.log("    },");
        console2.log("  ],");
        console2.log("} as const;\n");

        console2.log(string.concat("// Default planId: ", vm.toString(planId)));
        console2.log("\n=== End snippets ===\n");
    }

    function _configKeyAndName() internal view returns (string memory key, string memory name) {
        if (block.chainid == 31337) return ("local", "anvil");
        return ("baseTestnet", "base-sepolia");
    }

    // --- Env helpers ---

    function _readOptionalAddress(string memory key) internal view returns (address addr) {
        try vm.envAddress(key) returns (address v) {
            addr = v;
        } catch {
            addr = address(0);
        }
    }

    function _readOptionalUint(string memory key) internal view returns (uint256 v) {
        try vm.envUint(key) returns (uint256 x) {
            v = x;
        } catch {
            v = 0;
        }
    }

    function _envOrUint(string memory key, uint256 defaultVal) internal view returns (uint256 v) {
        try vm.envUint(key) returns (uint256 x) {
            v = x;
        } catch {
            v = defaultVal;
        }
    }

    function _readOptionalBool(string memory key, bool defaultVal) internal view returns (bool v) {
        // envBool accepts "true/false"; if it's missing, return default.
        try vm.envBool(key) returns (bool x) {
            v = x;
        } catch {
            // Accept numeric "0/1" as a fallback.
            try vm.envUint(key) returns (uint256 y) {
                v = (y != 0);
            } catch {
                v = defaultVal;
            }
        }
    }

    function _ffiIncreaseTime(uint256 secondsForward) internal {
        // Requires: --ffi and ETH_RPC_URL env var.
        string[] memory cmd = new string[](4);
        cmd[0] = "cast";
        cmd[1] = "rpc";
        cmd[2] = "evm_increaseTime";
        cmd[3] = vm.toString(secondsForward);
        vm.ffi(cmd);
    }

    function _ffiMine() internal {
        string[] memory cmd = new string[](3);
        cmd[0] = "cast";
        cmd[1] = "rpc";
        cmd[2] = "evm_mine";
        vm.ffi(cmd);
    }
}
