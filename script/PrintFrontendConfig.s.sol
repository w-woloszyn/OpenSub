// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

/**
 * @title PrintFrontendConfig
 * @notice Utility script that prints ready-to-copy snippets for:
 *   - frontend/config/addresses.ts
 *   - frontend/config/tokens.ts
 *
 * Use this if you already deployed contracts and just want to generate
 * paste-ready config blocks.
 *
 * Required env vars:
 *  - OPENSUB_ADDRESS=0x...
 *  - OPENSUB_DEPLOY_BLOCK=<uint>
 *  - TOKEN_ADDRESS=0x...
 *
 * Optional env vars:
 *  - CONFIG_KEY=local|baseTestnet     (defaults based on chainid)
 *  - CHAIN_NAME=<string>             (defaults: anvil / base-sepolia)
 *  - TOKEN_SYMBOL=<string>           (default: mUSDC)
 *  - TOKEN_NAME=<string>             (default: Mock USD Coin)
 *  - TOKEN_DECIMALS=<uint>           (default: 6)
 *  - DEFAULT_PLAN_ID=<uint>          (optional; printed as a comment)
 */
contract PrintFrontendConfig is Script {
    function run() external {
        address openSub = vm.envAddress("OPENSUB_ADDRESS");
        uint256 deployBlock = vm.envUint("OPENSUB_DEPLOY_BLOCK");
        address token = vm.envAddress("TOKEN_ADDRESS");

        (string memory key, string memory chainName) = _configKeyAndName();

        string memory symbol = _readOptionalString("TOKEN_SYMBOL", "mUSDC");
        string memory name = _readOptionalString("TOKEN_NAME", "Mock USD Coin");
        uint8 decimals = uint8(_readOptionalUint("TOKEN_DECIMALS", 6));

        uint256 planId = _readOptionalUint("DEFAULT_PLAN_ID", 0);

        // NOTE: use an explicit struct literal to avoid any ambiguity in Solidity parsing.
        _printSnippets(
            PrintParams({
                key: key,
                chainName: chainName,
                openSub: openSub,
                deployBlock: deployBlock,
                token: token,
                tokenSymbol: symbol,
                tokenName: name,
                tokenDecimals: decimals,
                defaultPlanId: planId
            })
        );
    }

    // -----------------
    // Internal helpers
    // -----------------

    struct PrintParams {
        string key;
        string chainName;
        address openSub;
        uint256 deployBlock;
        address token;
        string tokenSymbol;
        string tokenName;
        uint8 tokenDecimals;
        uint256 defaultPlanId;
    }

    function _printSnippets(PrintParams memory p) internal {
        console2.log("\n=== Paste-ready frontend snippets ===");
        console2.log(string.concat("// chainId: ", vm.toString(block.chainid)));
        if (p.defaultPlanId != 0) {
            console2.log(string.concat("// defaultPlanId: ", vm.toString(p.defaultPlanId)));
        }

        console2.log("\n// frontend/config/addresses.ts  (replace the matching block)");
        console2.log(string.concat("  ", p.key, ": {"));
        console2.log(string.concat("    chainName: \"", p.chainName, "\","));
        console2.log(string.concat("    openSub: \"", vm.toString(p.openSub), "\","));
        console2.log(string.concat("    deployBlock: ", vm.toString(p.deployBlock), "n,"));
        console2.log("  },");

        console2.log("\n// frontend/config/tokens.ts  (replace the matching block)");
        console2.log(string.concat("  ", p.key, ": ["));
        console2.log("    {");
        console2.log(string.concat("      symbol: \"", p.tokenSymbol, "\","));
        console2.log(string.concat("      name: \"", p.tokenName, "\","));
        console2.log(string.concat("      address: \"", vm.toString(p.token), "\","));
        console2.log(string.concat("      decimals: ", vm.toString(uint256(p.tokenDecimals)), ","));
        console2.log("    },");
        console2.log("  ],");

        console2.log("\n// Optional: .env.local (if your app uses env-based config)");
        if (_eq(p.key, "local")) {
            console2.log(string.concat("NEXT_PUBLIC_OPENSUB_ADDRESS_LOCAL=", vm.toString(p.openSub)));
            console2.log(string.concat("NEXT_PUBLIC_OPENSUB_DEPLOY_BLOCK_LOCAL=", vm.toString(p.deployBlock)));
            console2.log(string.concat("NEXT_PUBLIC_DEFAULT_TOKEN_LOCAL=", vm.toString(p.token)));
        } else {
            console2.log(string.concat("NEXT_PUBLIC_OPENSUB_ADDRESS_BASE_TESTNET=", vm.toString(p.openSub)));
            console2.log(string.concat("NEXT_PUBLIC_OPENSUB_DEPLOY_BLOCK_BASE_TESTNET=", vm.toString(p.deployBlock)));
            console2.log(string.concat("NEXT_PUBLIC_DEFAULT_TOKEN_BASE_TESTNET=", vm.toString(p.token)));
        }
        console2.log("=================================\n");
    }

    function _configKeyAndName() internal returns (string memory key, string memory name) {
        // Allow explicit overrides.
        try vm.envString("CONFIG_KEY") returns (string memory k) {
            if (bytes(k).length != 0) key = k;
        } catch {}

        try vm.envString("CHAIN_NAME") returns (string memory n) {
            if (bytes(n).length != 0) name = n;
        } catch {}

        // Defaults based on chain id.
        if (bytes(key).length == 0) {
            if (block.chainid == 31337) key = "local";
            else key = "baseTestnet";
        }

        if (bytes(name).length == 0) {
            if (_eq(key, "local")) name = "anvil";
            else name = "base-sepolia";
        }
    }

    function _readOptionalUint(string memory key, uint256 defaultValue) internal returns (uint256 v) {
        try vm.envUint(key) returns (uint256 x) {
            v = x;
        } catch {
            v = defaultValue;
        }
    }

    function _readOptionalString(string memory key, string memory defaultValue) internal returns (string memory v) {
        try vm.envString(key) returns (string memory x) {
            if (bytes(x).length != 0) return x;
        } catch {}
        return defaultValue;
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
