import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Req = {
  userOpHash?: string;
};

function mustEnv(name: string) {
  const v = process.env[name];
  if (!v || v.trim().length === 0) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

async function rpc(url: string, method: string, params: any[]) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method,
      params,
    }),
  });
  const json = await res.json();
  if (!res.ok) {
    throw new Error(json?.error?.message ?? `RPC ${method} failed`);
  }
  return json?.result ?? null;
}

export async function POST(req: Request) {
  try {
    const bundler = mustEnv("OPENSUB_AA_BUNDLER_URL");
    const body = (await req.json().catch(() => ({}))) as Req;
    const userOpHash = body.userOpHash?.trim();
    if (!userOpHash) {
      return NextResponse.json({ ok: false, error: "Missing userOpHash" }, { status: 400 });
    }

    const receipt = await rpc(bundler, "eth_getUserOperationReceipt", [userOpHash]);
    const userOp = await rpc(bundler, "eth_getUserOperationByHash", [userOpHash]);

    return NextResponse.json({ ok: true, receipt, userOp });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message ?? String(e) }, { status: 500 });
  }
}
