import { NextResponse } from "next/server";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

// Required because this route spawns a local process (the Rust AA CLI).
export const runtime = "nodejs";

type Req = {
  salt?: number;
  subscriptionId?: number | string;
  ownerPrivateKey?: string;
  smartAccount?: string;
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

function extractUserOpHash(logs: string): string | null {
  const m = logs.match(/userOpHash:\s*(0x[a-fA-F0-9]{64})/);
  return m ? m[1] : null;
}

function extractTxHash(logs: string): string | null {
  const matches = [...logs.matchAll(/transactionHash\"?:\s*\"(0x[a-fA-F0-9]{64})\"/g)];
  if (!matches.length) return null;
  return matches[matches.length - 1]?.[1] ?? null;
}

async function runBinary(args: {
  binPath: string;
  cwd: string;
  argv: string[];
  env?: NodeJS.ProcessEnv;
}) {
  return new Promise<{ stdout: string; stderr: string }>((resolve, reject) => {
    const child = spawn(args.binPath, args.argv, {
      cwd: args.cwd,
      env: args.env ?? process.env,
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
    mustEnv("OPENSUB_AA_BUNDLER_URL");
    mustEnv("OPENSUB_AA_ENTRYPOINT");
    mustEnv("OPENSUB_AA_FACTORY");
    mustEnv("OPENSUB_AA_PAYMASTER_URL");
    mustEnv("OPENSUB_AA_GAS_MANAGER_POLICY_ID");

    const body = (await req.json().catch(() => ({}))) as Req;
    const salt = body.salt ?? 0;
    const ownerPrivateKey = body.ownerPrivateKey?.trim();
    const smartAccountHint = body.smartAccount?.trim();
    const subIdRaw = body.subscriptionId ?? 0;
    const subId = Number(subIdRaw);

    if (!ownerPrivateKey) {
      return NextResponse.json(
        { ok: false, error: "Missing ownerPrivateKey (generate one in the browser first)." },
        { status: 400 }
      );
    }
    if (!Number.isFinite(subId) || subId <= 0) {
      return NextResponse.json(
        { ok: false, error: "Missing or invalid subscriptionId." },
        { status: 400 }
      );
    }

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

    const argv = [
      "resume",
      "--deployment",
      deploymentPath,
      "--json",
      "--salt",
      String(salt),
      "--subscription-id",
      String(subId),
      "--sponsor-gas",
      "--no-wait",
    ];
    const gasMult = process.env.OPENSUB_AA_GAS_MULTIPLIER_BPS;
    if (gasMult && Number(gasMult) > 0) {
      argv.push("--gas-multiplier-bps", String(Number(gasMult)));
    }

    const env = {
      ...process.env,
      OPENSUB_AA_OWNER_PRIVATE_KEY: ownerPrivateKey,
    };

    let stdout = "";
    let stderr = "";
    try {
      ({ stdout, stderr } = await runBinary({ binPath, cwd: repoRoot, argv, env }));
    } catch (e: any) {
      const msg = e?.message ?? String(e);
      if (msg.includes("timed out waiting for userOp receipt")) {
        return NextResponse.json({
          ok: true,
          pending: true,
          userOpHash: extractUserOpHash(msg),
          txHash: extractTxHash(msg),
          smartAccount: smartAccountHint ?? null,
          error: "Timed out waiting for userOp receipt. Use 'Check UserOp status' or the explorer links.",
          logs: msg,
        });
      }
      throw e;
    }

    const parsed = JSON.parse(stdout.trim()) as {
      owner: string;
      smartAccount: string;
      envPath: string | null;
    };

    const userOpHash = extractUserOpHash(stderr);
    const txHash = extractTxHash(stderr);

    return NextResponse.json({
      ok: true,
      pending: true,
      result: {
        ...parsed,
        userOpHash,
        txHash,
      },
      logs: stderr,
    });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message ?? String(e) }, { status: 500 });
  }
}
