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

# --- Config ---
ANVIL_HOST="${ANVIL_HOST:-127.0.0.1}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
CHAIN_ID="${CHAIN_ID:-31337}"
RPC_URL="${RPC_URL:-http://${ANVIL_HOST}:${ANVIL_PORT}}"
PLAN_INTERVAL_SECONDS="${PLAN_INTERVAL_SECONDS:-30}"   # keep small for fast demo

# Keep temp artifacts? (default: no)
KEEP_SECRETS="${KEEP_SECRETS:-0}"
KEEP_ANVIL_RUNNING="${KEEP_ANVIL_RUNNING:-0}"

mkdir -p .secrets
ANVIL_LOG=".secrets/anvil.log"
DEMO_LOG=".secrets/demo_scenario.log"
DEPLOY_FILE=".secrets/anvil-deployment.json"
KEEPER_STATE=".secrets/keeper-state.json"

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

echo "== OpenSub demo-local =="
echo "RPC: ${RPC_URL}"
echo "Plan interval seconds: ${PLAN_INTERVAL_SECONDS}"
echo ""

# --- Start Anvil ---
rm -f "${ANVIL_LOG}"
anvil --chain-id "${CHAIN_ID}" --port "${ANVIL_PORT}" --host "${ANVIL_HOST}" >"${ANVIL_LOG}" 2>&1 &
ANVIL_PID=$!

# Wait for anvil to be up
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
# Anvil prints:
# Private Keys
# (0) 0x...
# (1) 0x...
# ...
parse_pk() {
  local idx="$1"
  awk -v idx="(${idx})" '
    $0 ~ /^Private Keys/ {flag=1; next}
    flag && $1 == idx {print $2; exit}
  ' "${ANVIL_LOG}"
}

# Parse keys (robust against slow log flush)
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
  echo "Tip: anvil output format may have changed; re-run without redirect to inspect."
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

# Extract values from output
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

# --- Identify subscription id for subscriber (use mapping) ---
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

# --- Make it due (warp time + mine) so keeper has something to do ---
echo "Warping time forward by $((PLAN_INTERVAL_SECONDS + 1)) seconds to make subscription due..."
cast rpc evm_increaseTime $((PLAN_INTERVAL_SECONDS + 1)) --rpc-url "${RPC_URL}" >/dev/null
cast rpc evm_mine --rpc-url "${RPC_URL}" >/dev/null

DUE="$(cast call "${OPENSUB_ADDR}" "isDue(uint256)(bool)" "${SUB_ID}" --rpc-url "${RPC_URL}" | tr -d '\n')"
echo "isDue(subscriptionId=${SUB_ID}) => ${DUE}"
echo ""
if [[ "${DUE}" != "true" ]]; then
  echo "ERROR: subscription is not due after time-warp. Check PLAN_INTERVAL_SECONDS and DemoScenario output."
  echo "DemoScenario log: ${DEMO_LOG}"
  exit 1
fi


# --- Run keeper once to collect ---
echo "Running keeper (once) — it should call collect() for due subscriptions..."
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
  --tx-timeout-seconds 30 \
  --pending-ttl-seconds 120

echo ""
echo "Post-keeper checks:"
DUE2="$(cast call "${OPENSUB_ADDR}" "isDue(uint256)(bool)" "${SUB_ID}" --rpc-url "${RPC_URL}" | tr -d '\n')"
echo "isDue(subscriptionId=${SUB_ID}) => ${DUE2} (expected: false)"
echo ""
if [[ "${DUE2}" != "false" ]]; then
  echo "ERROR: keeper did not clear due status (expected isDue=false)."
  echo "Tip: inspect keeper logs above and check that it discovered Subscribed logs and submitted collect()."
  exit 1
fi

echo "Done."
echo "Artifacts (ignored by git):"
echo "  ${DEPLOY_FILE}"
echo "  ${KEEPER_STATE}"
if [[ "${KEEP_ANVIL_RUNNING}" == "1" ]]; then
  echo ""
  echo "KEEP_ANVIL_RUNNING=1 set; leaving anvil running on ${RPC_URL} (pid=${ANVIL_PID})"
  echo "Press Ctrl+C to stop if this is your current shell session."
  wait "${ANVIL_PID}"
fi
