import { NextResponse } from "next/server";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Req = {
  ownerPrivateKey?: string;
  salt?: number;
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
    // Required env for account derivation.
    mustEnv("OPENSUB_AA_ENTRYPOINT");
    mustEnv("OPENSUB_AA_FACTORY");

    const body = (await req.json().catch(() => ({}))) as Req;
    const ownerPrivateKey = body.ownerPrivateKey?.trim();
    const salt = body.salt ?? 0;

    if (!ownerPrivateKey) {
      return NextResponse.json({ ok: false, error: "Missing ownerPrivateKey" }, { status: 400 });
    }

    const repoRoot = findRepoRoot(process.cwd());
    const binPath = path.join(repoRoot, "aa-rs", "target", "release", "opensub-aa");
    const deploymentPath = path.join(repoRoot, "deployments", "base-sepolia.json");

    if (!fs.existsSync(binPath)) {
      return NextResponse.json(
        {
          ok: false,
          error: "Missing aa-rs binary. Build it first: cargo build --release --manifest-path aa-rs/Cargo.toml",
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
      "account",
      "--deployment",
      deploymentPath,
      "--json",
      "--salt",
      String(salt),
    ];

    const env = {
      ...process.env,
      OPENSUB_AA_OWNER_PRIVATE_KEY: ownerPrivateKey,
    };

    const { stdout, stderr } = await runBinary({ binPath, cwd: repoRoot, argv, env });
    const parsed = JSON.parse(stdout.trim()) as {
      owner: string;
      smartAccount: string;
      envPath: string | null;
    };

    return NextResponse.json({ ok: true, result: parsed, logs: stderr });
  } catch (e: any) {
    return NextResponse.json(
      { ok: false, error: e?.message ?? String(e) },
      { status: 500 }
    );
  }
}
