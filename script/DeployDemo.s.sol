// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {OpenSub} from "src/OpenSub.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

/**
 * DeployDemo
 *
 * Deploys:
 *  - MockERC20 (mUSDC, 6 decimals)
 *  - OpenSub
 *  - A demo plan
 *  - Mints demo tokens to merchant, and optionally to a second subscriber wallet
 *
 * Prints paste-ready snippets for:
 *  - frontend/config/addresses.ts
 *  - frontend/config/tokens.ts
 *
 * NOTE:
 *  - "deployBlock" printed here is a SAFE LOWER BOUND for log scanning.
 *    It's fine (and often safer) to scan from a bit earlier.
 */
contract DeployDemo is Script {
    // Token defaults
    uint8 internal constant TOKEN_DECIMALS = 6;

    // Plan defaults (override via env)
    uint256 internal constant PLAN_PRICE_DEFAULT = 10_000_000; // 10.000000
    uint40 internal constant PLAN_INTERVAL_DEFAULT = 30 days;
    uint16 internal constant PLAN_COLLECTOR_FEE_BPS_DEFAULT = 100; // 1%

    // Mint defaults (override via env)
    uint256 internal constant MINT_TO_MERCHANT_DEFAULT = 10_000 * 10 ** uint256(TOKEN_DECIMALS);
    uint256 internal constant MINT_TO_SUBSCRIBER_DEFAULT = 100 * 10 ** uint256(TOKEN_DECIMALS);

    function run() external {
        console2.log("=== DeployDemo ===");
        console2.log("chainid:", vm.toString(block.chainid));

        // Optional overrides
        uint256 planPrice = _envOrUint("PLAN_PRICE", PLAN_PRICE_DEFAULT);
        uint40 planInterval = uint40(_envOrUint("PLAN_INTERVAL_SECONDS", uint256(PLAN_INTERVAL_DEFAULT)));
        uint16 planFeeBps = uint16(_envOrUint("PLAN_COLLECTOR_FEE_BPS", uint256(PLAN_COLLECTOR_FEE_BPS_DEFAULT)));

        uint256 mintToMerchant = _envOrUint("MINT_TO_MERCHANT", MINT_TO_MERCHANT_DEFAULT);
        uint256 mintToSubscriber = _envOrUint("MINT_TO_SUBSCRIBER", MINT_TO_SUBSCRIBER_DEFAULT);

        // 1) Deploy token + OpenSub
        vm.startBroadcast();
        MockERC20 token = new MockERC20("Mock USD Coin", "mUSDC", TOKEN_DECIMALS);
        OpenSub deployed = new OpenSub();
        vm.stopBroadcast();

        // Capture the current block number as a safe lower bound for log scanning.
        uint256 tokenDeployBlock = block.number;
        uint256 openSubDeployBlock = block.number;

        // 2) Create a plan from the broadcaster (merchant)
        vm.startBroadcast();
        uint256 planId = deployed.createPlan(address(token), planPrice, planInterval, planFeeBps);
        vm.stopBroadcast();

        // Resolve merchant from plan storage (merchant = creator)
        (address merchant,,,,,,) = deployed.plans(planId);

        // 3) Mint demo tokens
        vm.startBroadcast();
        token.mint(merchant, mintToMerchant);
        vm.stopBroadcast();

        address subscriber = _readOptionalAddress("SUBSCRIBER");
        if (subscriber == address(0)) {
            // Optional: derive from SUBSCRIBER_PK (uint256 private key)
            uint256 subscriberPk = _readOptionalUint("SUBSCRIBER_PK");
            if (subscriberPk != 0) {
                subscriber = vm.addr(subscriberPk);
            }
        }

        if (subscriber != address(0)) {
            vm.startBroadcast();
            token.mint(subscriber, mintToSubscriber);
            vm.stopBroadcast();
        }

        console2.log("\n--- Deployed ---");
        console2.log("Token (mUSDC):", address(token));
        console2.log("OpenSub:", address(deployed));
        console2.log("Token deploy block (lower bound):", tokenDeployBlock);
        console2.log("OpenSub deploy block (lower bound):", openSubDeployBlock);
        console2.log("Demo planId:", planId);
        console2.log("Plan price:", planPrice);
        console2.log("Plan interval (seconds):", uint256(planInterval));
        console2.log("Plan collector fee (bps):", uint256(planFeeBps));
        console2.log("Merchant:", merchant);
        console2.log("Minted to merchant:", mintToMerchant);

        if (subscriber != address(0)) {
            console2.log("Subscriber:", subscriber);
            console2.log("Minted to subscriber:", mintToSubscriber);
        } else {
            console2.log("Subscriber: (not provided; set SUBSCRIBER or SUBSCRIBER_PK to auto-mint)");
        }

        _printPasteReadyFrontendConfig(
            address(deployed), openSubDeployBlock, address(token), tokenDeployBlock, TOKEN_DECIMALS, planId
        );

        console2.log("\nFrontend config tips:");
        console2.log("- Set NEXT_PUBLIC_OPENSUB_ADDRESS_* = OpenSub");
        console2.log("- Set NEXT_PUBLIC_OPENSUB_DEPLOY_BLOCK_* = OpenSub deploy block (or earlier)");
        console2.log("- Set NEXT_PUBLIC_DEFAULT_TOKEN_* = token address (optional)");
        console2.log("\nDone.");
    }

    function _printPasteReadyFrontendConfig(
        address openSub,
        uint256 openSubDeployBlock,
        address token,
        uint256, /*tokenDeployBlock*/
        uint8 tokenDecimals,
        uint256 planId
    ) internal view {
        (string memory key, string memory name) = _configKeyAndName();

        // We recommend scanning from slightly earlier to be resilient.
        uint256 fromBlock = openSubDeployBlock;
        if (block.chainid != 31337) {
            // Public RPCs sometimes behave oddly around "latest"; use a small buffer.
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
        // Default to Base Sepolia as "Base testnet".
        return ("baseTestnet", "base-sepolia");
    }

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
}
