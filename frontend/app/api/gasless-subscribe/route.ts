import { NextResponse } from "next/server";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { createPublicClient, http } from "viem";
import { baseSepolia } from "viem/chains";

import { openSubAbi } from "@/abi/openSubAbi";

// Required because this route spawns a local process (the Rust AA CLI).
export const runtime = "nodejs";

type Req = {
  // Demo inputs
  salt?: number;
  allowancePeriods?: number;
  mintAmountRaw?: string; // base units (e.g. 10_000_000 for 10 mUSDC)
};

function findRepoRoot(start: string): string {
  let dir = start;
  for (let i = 0; i < 8; i++) {
    if (fs.existsSync(path.join(dir, "deployments")) && fs.existsSync(path.join(dir, "aa-rs"))) {
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return start;
}

function mustEnv(name: string) {
  const v = process.env[name];
  if (!v || v.trim().length === 0) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

async function runBinary(args: {
  binPath: string;
  cwd: string;
  argv: string[];
}) {
  return new Promise<{ stdout: string; stderr: string }>((resolve, reject) => {
    const child = spawn(args.binPath, args.argv, {
      cwd: args.cwd,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (d) => (stdout += d.toString("utf8")));
    child.stderr.on("data", (d) => (stderr += d.toString("utf8")));

    child.on("error", (err) => reject(err));
    child.on("close", (code) => {
      if (code === 0) return resolve({ stdout, stderr });
      reject(new Error(`opensub-aa exited with code ${code}.\n${stderr}`));
    });
  });
}

export async function POST(req: Request) {
  try {
    // Validate required env for 6B flow.
    mustEnv("OPENSUB_AA_BUNDLER_URL");
    mustEnv("OPENSUB_AA_ENTRYPOINT");
    mustEnv("OPENSUB_AA_FACTORY");
    mustEnv("OPENSUB_AA_PAYMASTER_URL");
    mustEnv("OPENSUB_AA_GAS_MANAGER_POLICY_ID");

    const body = (await req.json().catch(() => ({}))) as Req;
    const salt = body.salt ?? 0;
    const allowancePeriods = body.allowancePeriods ?? 12;
    const mintAmountRaw = body.mintAmountRaw ?? "10000000";

    const repoRoot = findRepoRoot(process.cwd());
    const binPath = path.join(repoRoot, "aa-rs", "target", "release", "opensub-aa");
    const deploymentPath = path.join(repoRoot, "deployments", "base-sepolia.json");

    if (!fs.existsSync(binPath)) {
      return NextResponse.json(
        {
          ok: false,
          error:
            "Missing aa-rs binary. Build it first: cargo build --release --manifest-path aa-rs/Cargo.toml",
          expectedPath: binPath,
        },
        { status: 500 }
      );
    }

    if (!fs.existsSync(deploymentPath)) {
      return NextResponse.json(
        { ok: false, error: "Missing deployments/base-sepolia.json", expectedPath: deploymentPath },
        { status: 500 }
      );
    }

    const dep = JSON.parse(fs.readFileSync(deploymentPath, "utf8")) as {
      rpc?: string;
      openSub: string;
      planId: number;
      chainId: number;
    };

    // Run: sponsored subscribe with a new owner key.
    const argv = [
      "subscribe",
      "--deployment",
      deploymentPath,
      "--new-owner",
      "--json",
      "--salt",
      String(salt),
      "--allowance-periods",
      String(allowancePeriods),
      "--mint",
      mintAmountRaw,
      "--sponsor-gas",
    ];

    const { stdout, stderr } = await runBinary({ binPath, cwd: repoRoot, argv });

    const parsed = JSON.parse(stdout.trim()) as {
      owner: string;
      smartAccount: string;
      envPath: string | null;
    };

    // Post-check on-chain state.
    const rpcUrl = process.env.OPENSUB_AA_RPC_URL ?? dep.rpc ?? "https://sepolia.base.org";
    const client = createPublicClient({
      chain: baseSepolia,
      transport: http(rpcUrl),
    });

    const planId = BigInt(dep.planId);
    const subId = (await client.readContract({
      address: dep.openSub as `0x${string}`,
      abi: openSubAbi,
      functionName: "activeSubscriptionOf",
      args: [planId, parsed.smartAccount as `0x${string}`],
    })) as bigint;

    const hasAccess = subId !== 0n
      ? ((await client.readContract({
          address: dep.openSub as `0x${string}`,
          abi: openSubAbi,
          functionName: "hasAccess",
          args: [subId],
        })) as boolean)
      : false;

    return NextResponse.json({
      ok: true,
      deployment: { openSub: dep.openSub, planId: dep.planId, chainId: dep.chainId },
      result: {
        ...parsed,
        subscriptionId: subId.toString(),
        hasAccess,
      },
      // stderr includes human-readable logs from the CLI. We include it because this is demo-only.
      logs: stderr,
    });
  } catch (e: any) {
    return NextResponse.json(
      { ok: false, error: e?.message ?? String(e) },
      { status: 500 }
    );
  }
}
