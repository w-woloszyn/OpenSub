use crate::state::KeeperState;
use ethers::providers::Middleware;
use ethers::types::{Address, BlockNumber, Filter, H256, U256};
use eyre::{eyre, Result};
use std::cmp;
use std::time::Duration;

/// Event topic0 for:
/// Subscribed(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber, uint40 startTime, uint40 paidThrough)
///
/// We only need `subscriptionId` (topics[1]) so we avoid decoding log data.
fn subscribed_topic0() -> H256 {
    ethers::utils::id("Subscribed(uint256,uint256,address,uint40,uint40)")
}

pub async fn scan_new_subscriptions<M: Middleware>(
    client: &M,
    opensub: Address,
    start_block: u64,
    confirmations: u64,
    log_chunk_size: u64,
    state: &mut KeeperState,
) -> Result<usize> {
    let latest = client.get_block_number().await?.as_u64();
    let target = latest.saturating_sub(confirmations);

    // Determine scan start.
    let mut from = state.last_scanned_block.saturating_add(1);
    from = from.max(start_block);

    if from > target {
        tracing::debug!(
            from,
            target,
            "no new blocks to scan (waiting for confirmations)"
        );
        return Ok(0);
    }

    let topic0 = subscribed_topic0();

    // We'll accumulate in a BTreeSet to keep deterministic ordering.
    let mut ids = state.ids_set();
    let before_total = ids.len();

    let mut chunk = log_chunk_size.max(1);

    tracing::info!(
        from,
        to = target,
        confirmations,
        chunk,
        "scanning for Subscribed logs"
    );

    let mut cursor = from;
    while cursor <= target {
        let end = cmp::min(cursor.saturating_add(chunk - 1), target);

        // We may need to shrink the chunk size if the RPC rejects large ranges.
        let logs = match fetch_logs_with_retries(client, opensub, topic0, cursor, end).await {
            Ok(logs) => logs,
            Err(err) => {
                // Shrink range and retry (down to 10-block chunks).
                if chunk <= 10 {
                    return Err(err);
                }
                chunk = cmp::max(10, chunk / 2);
                tracing::warn!(
                    cursor,
                    end,
                    chunk,
                    "log fetch failed; reducing chunk size and retrying"
                );
                continue;
            }
        };

        for log in logs {
            if log.topics.len() < 2 {
                continue;
            }
            let id_u256 = U256::from_big_endian(log.topics[1].as_bytes());
            if id_u256 > U256::from(u64::MAX) {
                tracing::warn!(subscription_id = ?id_u256, "subscriptionId exceeds u64::MAX; skipping");
                continue;
            }
            ids.insert(id_u256.as_u64());
        }

        // Advance and record scan progress.
        state.last_scanned_block = end;
        cursor = end.saturating_add(1);
    }

    state.set_ids_from_set(ids);

    let after_total = state.subscription_ids.len();
    let discovered = after_total.saturating_sub(before_total);

    tracing::info!(
        discovered,
        last_scanned_block = state.last_scanned_block,
        total = after_total,
        "scan complete"
    );

    Ok(discovered)
}

async fn fetch_logs_with_retries<M: Middleware>(
    client: &M,
    opensub: Address,
    topic0: H256,
    from: u64,
    to: u64,
) -> Result<Vec<ethers::types::Log>> {
    if from > to {
        return Err(eyre!("invalid log range: from({from}) > to({to})"));
    }

    let filter = Filter::new()
        .address(opensub)
        .topic0(topic0)
        .from_block(BlockNumber::Number(from.into()))
        .to_block(BlockNumber::Number(to.into()));

    // A few quick retries with exponential backoff help with flaky / rate-limited RPCs.
    let mut delay = Duration::from_millis(200);

    for attempt in 1..=3 {
        match client.get_logs(&filter).await {
            Ok(logs) => return Ok(logs),
            Err(err) => {
                if attempt == 3 {
                    return Err(err.into());
                }
                tracing::warn!(
                    attempt,
                    from,
                    to,
                    sleep_ms = delay.as_millis() as u64,
                    error = %err,
                    "getLogs failed; retrying"
                );
                tokio::time::sleep(delay).await;
                delay = delay.saturating_mul(2);
            }
        }
    }

    Err(eyre!("unreachable"))
}
