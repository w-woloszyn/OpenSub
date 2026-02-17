\
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# --- Requirements ---
req() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found in PATH"; exit 1; }
}
req anvil
req forge
req cast
req cargo

# Pick a python interpreter (some systems only have python3).
PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN=python
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
  else
    echo "ERROR: python/python3 not found in PATH (needed to parse keeper state JSON)" >&2
    exit 1
  fi
fi

# --- Config ---
ANVIL_HOST="${ANVIL_HOST:-127.0.0.1}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
CHAIN_ID="${CHAIN_ID:-31337}"
RPC_URL="${RPC_URL:-http://${ANVIL_HOST}:${ANVIL_PORT}}"

# Keep interval small for fast local testing.
PLAN_INTERVAL_SECONDS="${PLAN_INTERVAL_SECONDS:-30}"

# Keep backoff tiny so we can demonstrate "backoff recorded" and then retry without waiting minutes.
SELFTEST_BACKOFF_SECONDS="${SELFTEST_BACKOFF_SECONDS:-2}"

# Keep temp artifacts? (default: no)
KEEP_SECRETS="${KEEP_SECRETS:-0}"
KEEP_ANVIL_RUNNING="${KEEP_ANVIL_RUNNING:-0}"

mkdir -p .secrets
ANVIL_LOG=".secrets/anvil.log"
DEMO_LOG=".secrets/demo_scenario.log"
DEPLOY_FILE=".secrets/anvil-deployment.json"
KEEPER_STATE=".secrets/keeper-selftest-state.json"

cleanup() {
  local code=$?
  set +e
  if [[ "${KEEP_ANVIL_RUNNING}" != "1" ]]; then
    if [[ -n "${ANVIL_PID:-}" ]]; then
      kill "${ANVIL_PID}" >/dev/null 2>&1 || true
    fi
  fi
  if [[ "${KEEP_SECRETS}" != "1" ]]; then
    rm -f "${ANVIL_LOG}" "${DEMO_LOG}"
  fi
  exit $code
}
trap cleanup EXIT INT TERM

echo "== OpenSub keeper self-test (Milestone 5.1) =="
echo "RPC: ${RPC_URL}"
echo "Plan interval seconds: ${PLAN_INTERVAL_SECONDS}"
echo "Self-test backoff seconds: ${SELFTEST_BACKOFF_SECONDS}"
echo ""

# --- Start Anvil ---
rm -f "${ANVIL_LOG}"
anvil --chain-id "${CHAIN_ID}" --port "${ANVIL_PORT}" --host "${ANVIL_HOST}" >"${ANVIL_LOG}" 2>&1 &
ANVIL_PID=$!

echo "Starting anvil (pid=${ANVIL_PID}) ..."
for _ in $(seq 1 80); do
  if cast chain-id --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

REMOTE_CHAIN_ID="$(cast chain-id --rpc-url "${RPC_URL}")"
if [[ "${REMOTE_CHAIN_ID}" != "${CHAIN_ID}" ]]; then
  echo "ERROR: Unexpected chainId. Expected ${CHAIN_ID}, got ${REMOTE_CHAIN_ID}."
  echo "Anvil log: ${ANVIL_LOG}"
  exit 1
fi
echo "Anvil ready (chainId=${REMOTE_CHAIN_ID})."
echo ""

# --- Parse default anvil keys (merchant/subscriber/keeper) from anvil log ---
parse_pk() {
  local idx="$1"
  awk -v idx="(${idx})" '
    $0 ~ /^Private Keys/ {flag=1; next}
    flag && $1 == idx {print $2; exit}
  ' "${ANVIL_LOG}"
}

MERCHANT_PK=""
SUBSCRIBER_PK=""
KEEPER_PK=""
for _ in $(seq 1 50); do
  MERCHANT_PK="$(parse_pk 0)"
  SUBSCRIBER_PK="$(parse_pk 1)"
  KEEPER_PK="$(parse_pk 2)"
  if [[ -n "${MERCHANT_PK}" && -n "${SUBSCRIBER_PK}" && -n "${KEEPER_PK}" ]]; then
    break
  fi
  sleep 0.05
done

if [[ -z "${MERCHANT_PK}" || -z "${SUBSCRIBER_PK}" || -z "${KEEPER_PK}" ]]; then
  echo "ERROR: Failed to parse anvil private keys from ${ANVIL_LOG}."
  exit 1
fi

MERCHANT_ADDR="$(cast wallet address --private-key "${MERCHANT_PK}")"
SUBSCRIBER_ADDR="$(cast wallet address --private-key "${SUBSCRIBER_PK}")"
KEEPER_ADDR="$(cast wallet address --private-key "${KEEPER_PK}")"

echo "Merchant:   ${MERCHANT_ADDR}"
echo "Subscriber: ${SUBSCRIBER_ADDR}"
echo "Keeper:     ${KEEPER_ADDR}"
echo ""

# --- Install deps (idempotent) ---
./script/install_deps.sh

# --- Run DemoScenario to seed plan+subscription ---
export ETH_RPC_URL="${RPC_URL}"
export PLAN_INTERVAL_SECONDS="${PLAN_INTERVAL_SECONDS}"
export SUBSCRIBER_PK="${SUBSCRIBER_PK}"

rm -f "${DEMO_LOG}"
echo "Running DemoScenario (deploy + create plan + subscribe)..."
forge script script/DemoScenario.s.sol \
  --rpc-url "${RPC_URL}" \
  --private-key "${MERCHANT_PK}" \
  --broadcast -vvv | tee "${DEMO_LOG}" >/dev/null

OPENSUB_ADDR="$(grep -Eo 'OpenSub:\s*0x[a-fA-F0-9]{40}' "${DEMO_LOG}" | tail -n 1 | awk '{print $2}')"
TOKEN_ADDR="$(grep -Eo 'Token \(mUSDC\):\s*0x[a-fA-F0-9]{40}' "${DEMO_LOG}" | tail -n 1 | awk '{print $3}')"
PLAN_ID="$(grep -Eo 'PlanId:\s*[0-9]+' "${DEMO_LOG}" | tail -n 1 | awk '{print $2}')"
OPEN_SUB_DEPLOY_BLOCK="$(grep -Eo 'OpenSub deploy block \(lower bound\):\s*[0-9]+' "${DEMO_LOG}" | tail -n 1 | awk '{print $6}')"

if [[ -z "${OPENSUB_ADDR}" || -z "${TOKEN_ADDR}" || -z "${PLAN_ID}" || -z "${OPEN_SUB_DEPLOY_BLOCK}" ]]; then
  echo "ERROR: Failed to parse DemoScenario output (OpenSub/Token/PlanId/deploy block)."
  echo "See: ${DEMO_LOG}"
  exit 1
fi

echo ""
echo "Deployed OpenSub: ${OPENSUB_ADDR}"
echo "Deployed Token:  ${TOKEN_ADDR}"
echo "PlanId:          ${PLAN_ID}"
echo "Start block:     ${OPEN_SUB_DEPLOY_BLOCK} (safe lower bound)"
echo ""

# --- Write deployment artifact for keeper (kept in .secrets to avoid dirtying repo) ---
cat > "${DEPLOY_FILE}" <<EOF
{
  "chainId": ${CHAIN_ID},
  "rpc": "${RPC_URL}",
  "openSub": "${OPENSUB_ADDR}",
  "startBlock": ${OPEN_SUB_DEPLOY_BLOCK},
  "planId": ${PLAN_ID},
  "token": "${TOKEN_ADDR}"
}
EOF

# --- Identify subscription id for subscriber ---
SUB_ID="$(cast call "${OPENSUB_ADDR}" \
  "activeSubscriptionOf(uint256,address)(uint256)" \
  "${PLAN_ID}" "${SUBSCRIBER_ADDR}" \
  --rpc-url "${RPC_URL}" | tr -d '\n')"

if [[ "${SUB_ID}" == "0" || -z "${SUB_ID}" ]]; then
  echo "ERROR: activeSubscriptionOf returned 0; subscription was not created."
  exit 1
fi
echo "SubscriptionId: ${SUB_ID}"
echo ""

# --- Read plan price (for exact allowance restore) ---
# plans(planId) returns: merchant, token, price, interval, collectorFeeBps, active, createdAt
PLAN_PRICE="$(
  cast call "${OPENSUB_ADDR}" \
    "plans(uint256)(address,address,uint256,uint40,uint16,bool,uint40)" \
    "${PLAN_ID}" \
    --rpc-url "${RPC_URL}" | sed -n '3p' | awk '{print $1}' | tr -d '\n'
)"
if [[ -z "${PLAN_PRICE}" ]]; then
  echo "ERROR: Failed to read plan price via plans(planId)."
  exit 1
fi
echo "Plan price (from chain): ${PLAN_PRICE}"
echo ""

# --- Make it due (warp time + mine) so keeper has something to do ---
echo "Warping time forward by $((PLAN_INTERVAL_SECONDS + 1)) seconds to make subscription due..."
cast rpc evm_increaseTime $((PLAN_INTERVAL_SECONDS + 1)) --rpc-url "${RPC_URL}" >/dev/null
cast rpc evm_mine --rpc-url "${RPC_URL}" >/dev/null

DUE="$(cast call "${OPENSUB_ADDR}" "isDue(uint256)(bool)" "${SUB_ID}" --rpc-url "${RPC_URL}" | tr -d '\n')"
echo "isDue(subscriptionId=${SUB_ID}) => ${DUE}"
echo ""
if [[ "${DUE}" != "true" ]]; then
  echo "ERROR: subscription is not due after time-warp."
  exit 1
fi

# === Self-test Part 1: Break allowance, run keeper, assert NO tx + backoff recorded ===
echo "== Part 1: Break subscriber allowance (approve 0) =="
cast send "${TOKEN_ADDR}" \
  "approve(address,uint256)" \
  "${OPENSUB_ADDR}" 0 \
  --private-key "${SUBSCRIBER_PK}" \
  --rpc-url "${RPC_URL}" >/dev/null

ALLOW0="$(cast call "${TOKEN_ADDR}" "allowance(address,address)(uint256)" "${SUBSCRIBER_ADDR}" "${OPENSUB_ADDR}" --rpc-url "${RPC_URL}" | tr -d '\n')"
echo "allowance(subscriber->OpenSub) => ${ALLOW0} (expected: 0)"
echo ""

MERCH_BAL_BEFORE="$(cast call "${TOKEN_ADDR}" "balanceOf(address)(uint256)" "${MERCHANT_ADDR}" --rpc-url "${RPC_URL}" | tr -d '\n')"

echo "Running keeper once (expect: NO tx, backoff recorded)..."
KEEPER_LOCK="${KEEPER_STATE%.*}.lock"
rm -f "${KEEPER_STATE}" "${KEEPER_LOCK}"

export KEEPER_PRIVATE_KEY="${KEEPER_PK}"
export OPENSUB_KEEPER_RPC_URL="${RPC_URL}"
export RUST_LOG="${RUST_LOG:-info}"

cargo run --release --manifest-path keeper-rs/Cargo.toml -- \
  --deployment "${DEPLOY_FILE}" \
  --state-file "${KEEPER_STATE}" \
  --once \
  --confirmations 0 \
  --log-chunk 2000 \
  --max-txs-per-cycle 5 \
  --tx-timeout-seconds 20 \
  --pending-ttl-seconds 60 \
  --backoff-base-seconds "${SELFTEST_BACKOFF_SECONDS}" \
  --backoff-max-seconds "${SELFTEST_BACKOFF_SECONDS}" \
  --plan-inactive-backoff-seconds "${SELFTEST_BACKOFF_SECONDS}" \
  --rpc-error-backoff-seconds 1 \
  --jitter-seconds 0

echo ""
DUE_AFTER_1="$(cast call "${OPENSUB_ADDR}" "isDue(uint256)(bool)" "${SUB_ID}" --rpc-url "${RPC_URL}" | tr -d '\n')"
echo "isDue(after keeper run 1) => ${DUE_AFTER_1} (expected: true)"
if [[ "${DUE_AFTER_1}" != "true" ]]; then
  echo "ERROR: due status cleared unexpectedly; keeper may have collected when it shouldn't."
  exit 1
fi

MERCH_BAL_AFTER_1="$(cast call "${TOKEN_ADDR}" "balanceOf(address)(uint256)" "${MERCHANT_ADDR}" --rpc-url "${RPC_URL}" | tr -d '\n')"
echo "merchant token balance before: ${MERCH_BAL_BEFORE}"
echo "merchant token balance after:  ${MERCH_BAL_AFTER_1} (expected: unchanged)"
if [[ "${MERCH_BAL_AFTER_1}" != "${MERCH_BAL_BEFORE}" ]]; then
  echo "ERROR: merchant token balance changed; expected no collect tx."
  exit 1
fi

echo ""
echo "Checking keeper state for backoff entry (InsufficientAllowance)..."
"${PYTHON_BIN}" - <<'PY' "${KEEPER_STATE}" "${SUB_ID}"
import json, sys
path = sys.argv[1]
sub = str(int(sys.argv[2]))
st = json.load(open(path))
ri = st.get("retries", {}).get(sub)
if not ri:
    print("ERROR: missing retries entry for subscriptionId", sub)
    sys.exit(2)
kind = ri.get("lastFailureKind")
nra = ri.get("nextRetryAt")
print("lastFailureKind:", kind)
print("nextRetryAt:", nra)
if kind not in ("insufficientAllowance", "InsufficientAllowance"):
    print("ERROR: expected lastFailureKind insufficientAllowance, got", kind)
    sys.exit(3)
PY

echo ""
echo "Backoff recorded ✅"
echo ""

# === Self-test Part 2: Restore allowance, wait out backoff, run keeper, assert success ===
echo "== Part 2: Restore allowance (approve plan price) =="
cast send "${TOKEN_ADDR}" \
  "approve(address,uint256)" \
  "${OPENSUB_ADDR}" "${PLAN_PRICE}" \
  --private-key "${SUBSCRIBER_PK}" \
  --rpc-url "${RPC_URL}" >/dev/null

ALLOW1="$(cast call "${TOKEN_ADDR}" "allowance(address,address)(uint256)" "${SUBSCRIBER_ADDR}" "${OPENSUB_ADDR}" --rpc-url "${RPC_URL}" | tr -d '\n')"
echo "allowance(subscriber->OpenSub) => ${ALLOW1} (expected: >= price ${PLAN_PRICE})"
echo ""

# Sleep until nextRetryAt (backoff) has elapsed, so we test the real retry path (no ignore-backoff).
SLEEP_SECS="$("${PYTHON_BIN}" - <<'PY' "${KEEPER_STATE}" "${SUB_ID}"
import json, sys, time
path = sys.argv[1]
sub = str(int(sys.argv[2]))
st = json.load(open(path))
nra = int(st.get("retries", {}).get(sub, {}).get("nextRetryAt", 0))
now = int(time.time())
sleep_s = max(0, nra - now + 1)
print(sleep_s)
PY
)"
if [[ "${SLEEP_SECS}" -gt 0 ]]; then
  echo "Waiting ${SLEEP_SECS}s for backoff to elapse..."
  sleep "${SLEEP_SECS}"
fi

echo "Running keeper again (expect: collect succeeds, backoff clears)..."
cargo run --release --manifest-path keeper-rs/Cargo.toml -- \
  --deployment "${DEPLOY_FILE}" \
  --state-file "${KEEPER_STATE}" \
  --once \
  --confirmations 0 \
  --log-chunk 2000 \
  --max-txs-per-cycle 5 \
  --tx-timeout-seconds 20 \
  --pending-ttl-seconds 60 \
  --backoff-base-seconds "${SELFTEST_BACKOFF_SECONDS}" \
  --backoff-max-seconds "${SELFTEST_BACKOFF_SECONDS}" \
  --plan-inactive-backoff-seconds "${SELFTEST_BACKOFF_SECONDS}" \
  --rpc-error-backoff-seconds 1 \
  --jitter-seconds 0

echo ""
DUE_AFTER_2="$(cast call "${OPENSUB_ADDR}" "isDue(uint256)(bool)" "${SUB_ID}" --rpc-url "${RPC_URL}" | tr -d '\n')"
echo "isDue(after keeper run 2) => ${DUE_AFTER_2} (expected: false)"
if [[ "${DUE_AFTER_2}" != "false" ]]; then
  echo "ERROR: keeper did not collect (expected isDue=false)."
  exit 1
fi

echo ""
echo "Checking keeper state: retries entry should be cleared after success..."
"${PYTHON_BIN}" - <<'PY' "${KEEPER_STATE}" "${SUB_ID}"
import json, sys
path = sys.argv[1]
sub = str(int(sys.argv[2]))
st = json.load(open(path))
ri = st.get("retries", {}).get(sub)
if ri:
    print("ERROR: retries entry still present after success:", ri)
    sys.exit(2)
print("retries entry cleared ✅")
PY

echo ""
echo "Keeper self-test PASSED ✅"
echo ""
echo "Artifacts (ignored by git):"
echo "  ${DEPLOY_FILE}"
echo "  ${KEEPER_STATE}"

if [[ "${KEEP_ANVIL_RUNNING}" == "1" ]]; then
  echo ""
  echo "KEEP_ANVIL_RUNNING=1 set; leaving anvil running on ${RPC_URL} (pid=${ANVIL_PID})"
  wait "${ANVIL_PID}"
fi
