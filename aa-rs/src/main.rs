mod bundler;
mod config;
mod encoding;
mod paymaster;
mod types;

use anyhow::{anyhow, Context, Result};
use bundler::BundlerClient;
use clap::{Args, Parser, Subcommand};
use config::load_deployment;
use ethers::abi::{Abi, AbiParser};
use ethers::prelude::*;
use ethers::providers::Middleware;
use paymaster::PaymasterClient;
use rand::rngs::OsRng;
use rand::RngCore;
use std::fs;
use std::path::PathBuf;
use std::str::FromStr;
use std::sync::Arc;
use std::time::Duration;
use types::UserOperation;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum StdoutMode {
    Normal,
    Json,
    OwnerEnvPath,
    OwnerAddress,
    SmartAccountAddress,
}

// Helper: in machine stdout modes, we keep stdout clean (so scripting can capture
// a single line). In these modes, all human-readable logs go to stderr.
macro_rules! outln {
    ($machine_mode:expr, $($arg:tt)*) => {{
        if $machine_mode {
            eprintln!($($arg)*);
        } else {
            println!($($arg)*);
        }
    }};
}

#[derive(Parser, Debug)]
#[command(name = "opensub-aa", version)]
struct Cli {
    #[command(subcommand)]
    cmd: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Print the counterfactual smart account address (and deployment status).
    Account(AccountArgs),

    /// Build + send a UserOperation that approves + subscribes.
    Subscribe(SubscribeArgs),

    /// Cancel a subscription (now or at period end).
    Cancel(CancelArgs),

    /// Resume auto-renew after a scheduled cancellation.
    Resume(ResumeArgs),

    /// Collect a due payment for a subscription.
    Collect(CollectArgs),
}

#[derive(Args, Debug)]
struct CommonArgs {
    /// Deployment artifact (OpenSub + token + planId).
    #[arg(long, default_value = "deployments/base-sepolia.json")]
    deployment: PathBuf,

    /// Override the chain RPC URL (otherwise uses deployment JSON).
    #[arg(long, env = "OPENSUB_AA_RPC_URL")]
    rpc: Option<String>,

    /// EntryPoint address.
    #[arg(long, env = "OPENSUB_AA_ENTRYPOINT")]
    entrypoint: String,

    /// SimpleAccountFactory address.
    #[arg(long, env = "OPENSUB_AA_FACTORY")]
    factory: String,

    /// Smart account owner private key.
    ///
    /// Recommended: set via env var OPENSUB_AA_OWNER_PRIVATE_KEY.
    #[arg(long, env = "OPENSUB_AA_OWNER_PRIVATE_KEY")]
    owner_private_key: Option<String>,

    /// Generate a new random owner key and write it under .secrets/ locally.
    ///
    /// This never prints the private key. The key is saved to a local file that should be
    /// gitignored (under the repo's `.secrets/` directory).
    ///
    /// If you want stdout-only scripting output, combine with:
    /// - `--print-owner-env-path` (prints the generated env file path), or
    /// - `--print-owner` / `--print-smart-account` (prints only the address).
    #[arg(long, default_value_t = false)]
    new_owner: bool,

    /// When used together with `--new-owner`, print the generated env file path to stdout as a
    /// single line (so scripts can `source "$(opensub-aa ... )"`).
    ///
    /// In this mode, all other output is written to stderr.
    #[arg(long, default_value_t = false)]
    print_owner_env_path: bool,

    /// Print ONLY the owner address to stdout as a single line.
    ///
    /// In this mode, all other output is written to stderr.
    #[arg(long, default_value_t = false)]
    print_owner: bool,

    /// Print ONLY the counterfactual smart account address to stdout as a single line.
    ///
    /// In this mode, all other output is written to stderr.
    #[arg(long, default_value_t = false)]
    print_smart_account: bool,

    /// Print a single JSON object to stdout:
    /// `{ "owner": "0x...", "smartAccount": "0x...", "envPath": "/abs/path" }`
    ///
    /// - `envPath` is `null` unless `--new-owner` is used.
    /// - All other logs are written to stderr.
    #[arg(long, default_value_t = false)]
    json: bool,

    /// CREATE2 salt for the smart account.
    #[arg(long, default_value_t = 0)]
    salt: u64,
}

#[derive(Args, Debug)]
struct AccountArgs {
    #[command(flatten)]
    common: CommonArgs,
}

#[derive(Args, Debug)]
struct SubscribeArgs {
    #[command(flatten)]
    common: CommonArgs,

    /// Bundler RPC URL (must support ERC-4337 JSON-RPC methods).
    #[arg(long, env = "OPENSUB_AA_BUNDLER_URL")]
    bundler: String,

    /// Sponsor gas using an ERC-7677 paymaster web service (Milestone 6B).
    ///
    /// For Base Sepolia with Alchemy Gas Manager, set:
    /// - OPENSUB_AA_PAYMASTER_URL=https://base-sepolia.g.alchemy.com/v2/<apiKey>
    /// - OPENSUB_AA_GAS_MANAGER_POLICY_ID=<your policy id>
    #[arg(long, default_value_t = false)]
    sponsor_gas: bool,

    /// Paymaster RPC URL (ERC-7677 paymaster web service).
    ///
    /// For Alchemy Gas Manager, this is an Alchemy HTTPS endpoint for the target chain.
    #[arg(long, env = "OPENSUB_AA_PAYMASTER_URL")]
    paymaster_url: Option<String>,

    /// Gas Manager policy id (Alchemy Gas Manager).
    #[arg(long, env = "OPENSUB_AA_GAS_MANAGER_POLICY_ID")]
    policy_id: Option<String>,

    /// Optional webhookData to include in paymaster requests.
    #[arg(long, env = "OPENSUB_AA_GAS_MANAGER_WEBHOOK_DATA")]
    webhook_data: Option<String>,

    /// Allowance in units of "periods" (allowance = price * periods).
    #[arg(long, default_value_t = 12)]
    allowance_periods: u64,

    /// Optional explicit allowance amount (overrides allowance-periods).
    #[arg(long)]
    allowance_amount: Option<String>,

    /// Optional: mint this many tokens (raw base units) to the smart account.
    ///
    /// Works on the repo's MockERC20 (mUSDC). Not valid for real tokens.
    #[arg(long)]
    mint: Option<String>,

    /// Optional: fund the smart account with ETH (amount in ETH, decimal string).
    ///
    /// This is used to pay the prefund for the UserOperation (no paymaster in 6A).
    #[arg(long)]
    fund_eth: Option<String>,

    /// Gas price multiplier in basis points (e.g. 15000 = 1.5x).
    ///
    /// Applied to maxFeePerGas and maxPriorityFeePerGas.
    #[arg(long, default_value_t = 10000, env = "OPENSUB_AA_GAS_MULTIPLIER_BPS")]
    gas_multiplier_bps: u64,

    /// Do not send the UserOperation; only build + estimate gas.
    #[arg(long)]
    dry_run: bool,

    /// Do not wait for the userOp receipt.
    #[arg(long)]
    no_wait: bool,

    /// Max seconds to wait for userOp receipt. Use 0 to disable timeout.
    #[arg(long, default_value_t = 180)]
    max_wait_seconds: u64,
}

#[derive(Args, Debug)]
struct CancelArgs {
    #[command(flatten)]
    common: CommonArgs,

    /// Bundler RPC URL (must support ERC-4337 JSON-RPC methods).
    #[arg(long, env = "OPENSUB_AA_BUNDLER_URL")]
    bundler: String,

    /// Sponsor gas using an ERC-7677 paymaster web service (Milestone 6B).
    #[arg(long, default_value_t = false)]
    sponsor_gas: bool,

    /// Paymaster RPC URL (ERC-7677 paymaster web service).
    #[arg(long, env = "OPENSUB_AA_PAYMASTER_URL")]
    paymaster_url: Option<String>,

    /// Gas Manager policy id (Alchemy Gas Manager).
    #[arg(long, env = "OPENSUB_AA_GAS_MANAGER_POLICY_ID")]
    policy_id: Option<String>,

    /// Optional webhookData to include in paymaster requests.
    #[arg(long, env = "OPENSUB_AA_GAS_MANAGER_WEBHOOK_DATA")]
    webhook_data: Option<String>,

    /// Subscription id to cancel.
    #[arg(long)]
    subscription_id: u64,

    /// If set, cancel at period end (non-renewing) instead of immediately.
    #[arg(long, default_value_t = false)]
    at_period_end: bool,

    /// Gas price multiplier in basis points (e.g. 15000 = 1.5x).
    #[arg(long, default_value_t = 10000, env = "OPENSUB_AA_GAS_MULTIPLIER_BPS")]
    gas_multiplier_bps: u64,

    /// Do not send the UserOperation; only build + estimate gas.
    #[arg(long)]
    dry_run: bool,

    /// Do not wait for the userOp receipt.
    #[arg(long)]
    no_wait: bool,

    /// Max seconds to wait for userOp receipt. Use 0 to disable timeout.
    #[arg(long, default_value_t = 180)]
    max_wait_seconds: u64,
}

#[derive(Args, Debug)]
struct ResumeArgs {
    #[command(flatten)]
    common: CommonArgs,

    /// Bundler RPC URL (must support ERC-4337 JSON-RPC methods).
    #[arg(long, env = "OPENSUB_AA_BUNDLER_URL")]
    bundler: String,

    /// Sponsor gas using an ERC-7677 paymaster web service (Milestone 6B).
    #[arg(long, default_value_t = false)]
    sponsor_gas: bool,

    /// Paymaster RPC URL (ERC-7677 paymaster web service).
    #[arg(long, env = "OPENSUB_AA_PAYMASTER_URL")]
    paymaster_url: Option<String>,

    /// Gas Manager policy id (Alchemy Gas Manager).
    #[arg(long, env = "OPENSUB_AA_GAS_MANAGER_POLICY_ID")]
    policy_id: Option<String>,

    /// Optional webhookData to include in paymaster requests.
    #[arg(long, env = "OPENSUB_AA_GAS_MANAGER_WEBHOOK_DATA")]
    webhook_data: Option<String>,

    /// Subscription id to resume.
    #[arg(long)]
    subscription_id: u64,

    /// Gas price multiplier in basis points (e.g. 15000 = 1.5x).
    #[arg(long, default_value_t = 10000, env = "OPENSUB_AA_GAS_MULTIPLIER_BPS")]
    gas_multiplier_bps: u64,

    /// Do not send the UserOperation; only build + estimate gas.
    #[arg(long)]
    dry_run: bool,

    /// Do not wait for the userOp receipt.
    #[arg(long)]
    no_wait: bool,

    /// Max seconds to wait for userOp receipt. Use 0 to disable timeout.
    #[arg(long, default_value_t = 180)]
    max_wait_seconds: u64,
}

#[derive(Args, Debug)]
struct CollectArgs {
    #[command(flatten)]
    common: CommonArgs,

    /// Bundler RPC URL (must support ERC-4337 JSON-RPC methods).
    #[arg(long, env = "OPENSUB_AA_BUNDLER_URL")]
    bundler: String,

    /// Sponsor gas using an ERC-7677 paymaster web service (Milestone 6B).
    #[arg(long, default_value_t = false)]
    sponsor_gas: bool,

    /// Paymaster RPC URL (ERC-7677 paymaster web service).
    #[arg(long, env = "OPENSUB_AA_PAYMASTER_URL")]
    paymaster_url: Option<String>,

    /// Gas Manager policy id (Alchemy Gas Manager).
    #[arg(long, env = "OPENSUB_AA_GAS_MANAGER_POLICY_ID")]
    policy_id: Option<String>,

    /// Optional webhookData to include in paymaster requests.
    #[arg(long, env = "OPENSUB_AA_GAS_MANAGER_WEBHOOK_DATA")]
    webhook_data: Option<String>,

    /// Subscription id to collect.
    #[arg(long)]
    subscription_id: u64,

    /// Gas price multiplier in basis points (e.g. 15000 = 1.5x).
    #[arg(long, default_value_t = 10000, env = "OPENSUB_AA_GAS_MULTIPLIER_BPS")]
    gas_multiplier_bps: u64,

    /// Do not send the UserOperation; only build + estimate gas.
    #[arg(long)]
    dry_run: bool,

    /// Do not wait for the userOp receipt.
    #[arg(long)]
    no_wait: bool,

    /// Max seconds to wait for userOp receipt. Use 0 to disable timeout.
    #[arg(long, default_value_t = 180)]
    max_wait_seconds: u64,
}

#[derive(Clone, Debug)]
struct TxArgs {
    bundler: String,
    sponsor_gas: bool,
    paymaster_url: Option<String>,
    policy_id: Option<String>,
    webhook_data: Option<String>,
    gas_multiplier_bps: u64,
    dry_run: bool,
    no_wait: bool,
    max_wait_seconds: u64,
}

impl From<&SubscribeArgs> for TxArgs {
    fn from(args: &SubscribeArgs) -> Self {
        Self {
            bundler: args.bundler.clone(),
            sponsor_gas: args.sponsor_gas,
            paymaster_url: args.paymaster_url.clone(),
            policy_id: args.policy_id.clone(),
            webhook_data: args.webhook_data.clone(),
            gas_multiplier_bps: args.gas_multiplier_bps,
            dry_run: args.dry_run,
            no_wait: args.no_wait,
            max_wait_seconds: args.max_wait_seconds,
        }
    }
}

impl From<&CancelArgs> for TxArgs {
    fn from(args: &CancelArgs) -> Self {
        Self {
            bundler: args.bundler.clone(),
            sponsor_gas: args.sponsor_gas,
            paymaster_url: args.paymaster_url.clone(),
            policy_id: args.policy_id.clone(),
            webhook_data: args.webhook_data.clone(),
            gas_multiplier_bps: args.gas_multiplier_bps,
            dry_run: args.dry_run,
            no_wait: args.no_wait,
            max_wait_seconds: args.max_wait_seconds,
        }
    }
}

impl From<&ResumeArgs> for TxArgs {
    fn from(args: &ResumeArgs) -> Self {
        Self {
            bundler: args.bundler.clone(),
            sponsor_gas: args.sponsor_gas,
            paymaster_url: args.paymaster_url.clone(),
            policy_id: args.policy_id.clone(),
            webhook_data: args.webhook_data.clone(),
            gas_multiplier_bps: args.gas_multiplier_bps,
            dry_run: args.dry_run,
            no_wait: args.no_wait,
            max_wait_seconds: args.max_wait_seconds,
        }
    }
}

impl From<&CollectArgs> for TxArgs {
    fn from(args: &CollectArgs) -> Self {
        Self {
            bundler: args.bundler.clone(),
            sponsor_gas: args.sponsor_gas,
            paymaster_url: args.paymaster_url.clone(),
            policy_id: args.policy_id.clone(),
            webhook_data: args.webhook_data.clone(),
            gas_multiplier_bps: args.gas_multiplier_bps,
            dry_run: args.dry_run,
            no_wait: args.no_wait,
            max_wait_seconds: args.max_wait_seconds,
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        // Always write logs to stderr so stdout can be used for script-friendly outputs.
        .with_writer(std::io::stderr)
        .init();

    let cli = Cli::parse();

    match cli.cmd {
        Command::Account(args) => cmd_account(args).await,
        Command::Subscribe(args) => cmd_subscribe(args).await,
        Command::Cancel(args) => cmd_cancel(args).await,
        Command::Resume(args) => cmd_resume(args).await,
        Command::Collect(args) => cmd_collect(args).await,
    }
}

async fn cmd_account(args: AccountArgs) -> Result<()> {
    let dep = load_deployment(&args.common.deployment, args.common.rpc.clone())?;

    let mode = stdout_mode(&args.common)?;
    let machine_mode = mode != StdoutMode::Normal;

    let provider =
        Provider::<Http>::try_from(dep.rpc_url.as_str())?.interval(Duration::from_millis(350));

    let chain_id = provider.get_chainid().await?.as_u64();
    if chain_id != dep.chain_id {
        return Err(anyhow!(
            "chainId mismatch: deployment has {}, RPC returned {}",
            dep.chain_id,
            chain_id
        ));
    }

    let entrypoint =
        Address::from_str(&args.common.entrypoint).context("invalid --entrypoint address")?;
    let factory_addr =
        Address::from_str(&args.common.factory).context("invalid --factory address")?;

    let (wallet, owner, owner_key_path) = load_or_generate_owner(&args.common, chain_id)?;
    let owner_env_path = owner_key_path.map(|p| p.canonicalize().unwrap_or(p));
    if let Some(p) = owner_env_path.as_ref() {
        match mode {
            StdoutMode::OwnerEnvPath => {
                // stdout: single line for scripting
                println!("{}", p.display());
                // stderr: human log
                eprintln!("generated new owner key; saved to {}", p.display());
            }
            StdoutMode::Json => {
                // JSON mode prints envPath inside the JSON object; keep logs on stderr.
                eprintln!("generated new owner key; saved to {}", p.display());
            }
            _ => {
                outln!(
                    machine_mode,
                    "generated new owner key; saved to {}",
                    p.display()
                );
            }
        }
    }

    let client = Arc::new(SignerMiddleware::new(provider.clone(), wallet));

    let (account, deployed) = compute_account_address(
        client.clone(),
        factory_addr,
        owner,
        U256::from(args.common.salt),
    )
    .await?;

    // Script-friendly JSON: print once to stdout.
    if mode == StdoutMode::Json {
        let env_path = owner_env_path.as_ref().map(|p| p.display().to_string());
        let out = serde_json::json!({
            "owner": encoding::fmt_address(owner),
            "smartAccount": encoding::fmt_address(account),
            "envPath": env_path,
        });
        println!("{}", out);
    }

    match mode {
        StdoutMode::OwnerAddress => println!("{}", owner),
        StdoutMode::SmartAccountAddress => println!("{}", account),
        _ => {}
    }

    outln!(machine_mode, "chainId:        {}", dep.chain_id);
    outln!(machine_mode, "entryPoint:     {}", entrypoint);
    outln!(machine_mode, "factory:        {}", factory_addr);
    outln!(machine_mode, "owner:          {}", owner);
    outln!(machine_mode, "smartAccount:   {}", account);
    outln!(machine_mode, "isDeployed:     {}", deployed);

    Ok(())
}

async fn cmd_subscribe(args: SubscribeArgs) -> Result<()> {
    let dep = load_deployment(&args.common.deployment, args.common.rpc.clone())?;

    let mode = stdout_mode(&args.common)?;
    let machine_mode = mode != StdoutMode::Normal;

    let provider =
        Provider::<Http>::try_from(dep.rpc_url.as_str())?.interval(Duration::from_millis(350));

    let chain_id = provider.get_chainid().await?.as_u64();
    if chain_id != dep.chain_id {
        return Err(anyhow!(
            "chainId mismatch: deployment has {}, RPC returned {}",
            dep.chain_id,
            chain_id
        ));
    }

    let entrypoint =
        Address::from_str(&args.common.entrypoint).context("invalid --entrypoint address")?;
    let factory_addr =
        Address::from_str(&args.common.factory).context("invalid --factory address")?;

    let (wallet, owner, owner_key_path) = load_or_generate_owner(&args.common, chain_id)?;
    let owner_env_path = owner_key_path.map(|p| p.canonicalize().unwrap_or(p));

    // Machine mode: allow scripts to capture the owner address without parsing logs.
    if mode == StdoutMode::OwnerAddress {
        println!("{}", owner);
    }

    if let Some(p) = owner_env_path.as_ref() {
        match mode {
            StdoutMode::OwnerEnvPath => {
                // stdout: single line for scripting
                println!("{}", p.display());
                // stderr: human logs
                eprintln!("generated new owner key; saved to {}", p.display());
            }
            StdoutMode::Json => {
                // JSON mode prints envPath inside the JSON object; keep logs on stderr.
                eprintln!("generated new owner key; saved to {}", p.display());
            }
            _ => {
                outln!(
                    machine_mode,
                    "generated new owner key; saved to {}",
                    p.display()
                );
            }
        }

        if args.fund_eth.is_some() {
            outln!(
                machine_mode,
                "note: --fund-eth requires the NEW owner EOA ({}) to have ETH for gas.",
                owner
            );
        }
    }

    let client = Arc::new(SignerMiddleware::new(provider.clone(), wallet.clone()));

    // Load plan price/token from OpenSub.
    let (plan_token, plan_price, plan_active) =
        read_plan(client.clone(), dep.open_sub, dep.plan_id).await?;
    if plan_token != dep.token {
        return Err(anyhow!(
            "deployment token {} does not match OpenSub plan token {}",
            dep.token,
            plan_token
        ));
    }
    if !plan_active {
        return Err(anyhow!("plan {} is inactive on-chain", dep.plan_id));
    }

    let salt = U256::from(args.common.salt);
    let (account, deployed) =
        compute_account_address(client.clone(), factory_addr, owner, salt).await?;

    // Machine mode: allow scripts to capture the smart account address without parsing logs.
    if mode == StdoutMode::SmartAccountAddress {
        println!("{}", account);
    }

    // Script-friendly JSON: print once to stdout early (before any long-running bundler calls).
    if mode == StdoutMode::Json {
        let env_path = owner_env_path.as_ref().map(|p| p.display().to_string());
        let out = serde_json::json!({
            "owner": encoding::fmt_address(owner),
            "smartAccount": encoding::fmt_address(account),
            "envPath": env_path,
        });
        println!("{}", out);
    }

    outln!(
        machine_mode,
        "smartAccount: {} (deployed={})",
        account,
        deployed
    );

    // Optional funding for prefund.
    if let Some(eth) = args.fund_eth.clone() {
        let amount_wei = ethers::utils::parse_ether(eth.clone())
            .with_context(|| format!("invalid --fund-eth value: {eth}"))?;
        fund_account_eth(client.clone(), account, amount_wei).await?;
    }

    // Optional mint amount (demo-only token).
    //
    // Important: this is now executed *inside the UserOperation* (as part of the executeBatch call),
    // so it can be sponsored by a paymaster in Milestone 6B.
    //
    // This only works for the repo's MockERC20, which has an unrestricted `mint(address,uint256)`.
    let mint_amount: Option<U256> = if let Some(mint_amount) = args.mint.clone() {
        let amt = U256::from_dec_str(&mint_amount)
            .with_context(|| format!("invalid --mint amount (expected integer): {mint_amount}"))?;
        if amt.is_zero() {
            None
        } else {
            Some(amt)
        }
    } else {
        None
    };

    // Compute allowance.
    let allowance_amount = if let Some(a) = args.allowance_amount.clone() {
        U256::from_dec_str(&a)
            .with_context(|| format!("invalid --allowance-amount (expected integer): {a}"))?
    } else {
        plan_price
            .checked_mul(U256::from(args.allowance_periods))
            .ok_or_else(|| anyhow!("allowance overflow: price * periods"))?
    };

    // Build batched approve + subscribe calldata via account.executeBatch.
    let (call_data, init_code, nonce) = build_userop_payload(
        client.clone(),
        entrypoint,
        factory_addr,
        dep.open_sub,
        dep.token,
        dep.plan_id,
        owner,
        salt,
        account,
        deployed,
        mint_amount,
        allowance_amount,
    )
    .await?;

    let tx_args: TxArgs = (&args).into();
    let got_receipt = send_userop(
        &provider,
        client.clone(),
        &wallet,
        entrypoint,
        chain_id,
        account,
        call_data,
        init_code,
        nonce,
        &tx_args,
        machine_mode,
    )
    .await?;

    if !got_receipt {
        return Ok(());
    }

    // Best-effort: print subscription id after receipt.
    let sub_id = active_subscription_of(client.clone(), dep.open_sub, dep.plan_id, account).await?;
    outln!(
        machine_mode,
        "\nactiveSubscriptionOf(planId={}, account={}) => {}",
        dep.plan_id,
        account,
        sub_id
    );

    let has_access = has_access(client.clone(), dep.open_sub, sub_id)
        .await
        .unwrap_or(false);
    outln!(machine_mode, "hasAccess({}) => {}", sub_id, has_access);

    Ok(())
}

async fn cmd_cancel(args: CancelArgs) -> Result<()> {
    let dep = load_deployment(&args.common.deployment, args.common.rpc.clone())?;

    let mode = stdout_mode(&args.common)?;
    let machine_mode = mode != StdoutMode::Normal;

    let provider =
        Provider::<Http>::try_from(dep.rpc_url.as_str())?.interval(Duration::from_millis(350));

    let chain_id = provider.get_chainid().await?.as_u64();
    if chain_id != dep.chain_id {
        return Err(anyhow!(
            "chainId mismatch: deployment has {}, RPC returned {}",
            dep.chain_id,
            chain_id
        ));
    }

    let entrypoint =
        Address::from_str(&args.common.entrypoint).context("invalid --entrypoint address")?;
    let factory_addr =
        Address::from_str(&args.common.factory).context("invalid --factory address")?;

    let (wallet, owner, owner_key_path) = load_or_generate_owner(&args.common, chain_id)?;
    let owner_env_path = owner_key_path.map(|p| p.canonicalize().unwrap_or(p));

    if mode == StdoutMode::OwnerAddress {
        println!("{}", owner);
    }

    if let Some(p) = owner_env_path.as_ref() {
        match mode {
            StdoutMode::OwnerEnvPath => {
                println!("{}", p.display());
                eprintln!("generated new owner key; saved to {}", p.display());
            }
            StdoutMode::Json => {
                eprintln!("generated new owner key; saved to {}", p.display());
            }
            _ => {
                outln!(
                    machine_mode,
                    "generated new owner key; saved to {}",
                    p.display()
                );
            }
        }
    }

    let client = Arc::new(SignerMiddleware::new(provider.clone(), wallet.clone()));

    let salt = U256::from(args.common.salt);
    let (account, deployed) =
        compute_account_address(client.clone(), factory_addr, owner, salt).await?;

    if mode == StdoutMode::SmartAccountAddress {
        println!("{}", account);
    }

    if mode == StdoutMode::Json {
        let env_path = owner_env_path.as_ref().map(|p| p.display().to_string());
        let out = serde_json::json!({
            "owner": encoding::fmt_address(owner),
            "smartAccount": encoding::fmt_address(account),
            "envPath": env_path,
        });
        println!("{}", out);
    }

    outln!(
        machine_mode,
        "smartAccount: {} (deployed={})",
        account,
        deployed
    );

    let sub_id = U256::from(args.subscription_id);
    let open_sub_abi = AbiParser::default()
        .parse(&["function cancel(uint256 subscriptionId, bool atPeriodEnd)"])?;
    let open_sub = Contract::new(dep.open_sub, open_sub_abi, client.clone());
    let cancel_calldata = open_sub
        .method::<_, ()>("cancel", (sub_id, args.at_period_end))?
        .calldata()
        .ok_or_else(|| anyhow!("failed to build cancel calldata"))?;

    let (call_data, init_code, nonce) = build_single_call_payload(
        client.clone(),
        entrypoint,
        factory_addr,
        owner,
        salt,
        account,
        deployed,
        dep.open_sub,
        cancel_calldata,
    )
    .await?;

    let tx_args: TxArgs = (&args).into();
    let _got_receipt = send_userop(
        &provider,
        client.clone(),
        &wallet,
        entrypoint,
        chain_id,
        account,
        call_data,
        init_code,
        nonce,
        &tx_args,
        machine_mode,
    )
    .await?;

    Ok(())
}

async fn cmd_resume(args: ResumeArgs) -> Result<()> {
    let dep = load_deployment(&args.common.deployment, args.common.rpc.clone())?;

    let mode = stdout_mode(&args.common)?;
    let machine_mode = mode != StdoutMode::Normal;

    let provider =
        Provider::<Http>::try_from(dep.rpc_url.as_str())?.interval(Duration::from_millis(350));

    let chain_id = provider.get_chainid().await?.as_u64();
    if chain_id != dep.chain_id {
        return Err(anyhow!(
            "chainId mismatch: deployment has {}, RPC returned {}",
            dep.chain_id,
            chain_id
        ));
    }

    let entrypoint =
        Address::from_str(&args.common.entrypoint).context("invalid --entrypoint address")?;
    let factory_addr =
        Address::from_str(&args.common.factory).context("invalid --factory address")?;

    let (wallet, owner, owner_key_path) = load_or_generate_owner(&args.common, chain_id)?;
    let owner_env_path = owner_key_path.map(|p| p.canonicalize().unwrap_or(p));

    if mode == StdoutMode::OwnerAddress {
        println!("{}", owner);
    }

    if let Some(p) = owner_env_path.as_ref() {
        match mode {
            StdoutMode::OwnerEnvPath => {
                println!("{}", p.display());
                eprintln!("generated new owner key; saved to {}", p.display());
            }
            StdoutMode::Json => {
                eprintln!("generated new owner key; saved to {}", p.display());
            }
            _ => {
                outln!(
                    machine_mode,
                    "generated new owner key; saved to {}",
                    p.display()
                );
            }
        }
    }

    let client = Arc::new(SignerMiddleware::new(provider.clone(), wallet.clone()));

    let salt = U256::from(args.common.salt);
    let (account, deployed) =
        compute_account_address(client.clone(), factory_addr, owner, salt).await?;

    if mode == StdoutMode::SmartAccountAddress {
        println!("{}", account);
    }

    if mode == StdoutMode::Json {
        let env_path = owner_env_path.as_ref().map(|p| p.display().to_string());
        let out = serde_json::json!({
            "owner": encoding::fmt_address(owner),
            "smartAccount": encoding::fmt_address(account),
            "envPath": env_path,
        });
        println!("{}", out);
    }

    outln!(
        machine_mode,
        "smartAccount: {} (deployed={})",
        account,
        deployed
    );

    let sub_id = U256::from(args.subscription_id);
    let open_sub_abi =
        AbiParser::default().parse(&["function unscheduleCancel(uint256 subscriptionId)"])?;
    let open_sub = Contract::new(dep.open_sub, open_sub_abi, client.clone());
    let resume_calldata = open_sub
        .method::<_, ()>("unscheduleCancel", (sub_id,))?
        .calldata()
        .ok_or_else(|| anyhow!("failed to build unscheduleCancel calldata"))?;

    let (call_data, init_code, nonce) = build_single_call_payload(
        client.clone(),
        entrypoint,
        factory_addr,
        owner,
        salt,
        account,
        deployed,
        dep.open_sub,
        resume_calldata,
    )
    .await?;

    let tx_args: TxArgs = (&args).into();
    let _got_receipt = send_userop(
        &provider,
        client.clone(),
        &wallet,
        entrypoint,
        chain_id,
        account,
        call_data,
        init_code,
        nonce,
        &tx_args,
        machine_mode,
    )
    .await?;

    Ok(())
}

async fn cmd_collect(args: CollectArgs) -> Result<()> {
    let dep = load_deployment(&args.common.deployment, args.common.rpc.clone())?;

    let mode = stdout_mode(&args.common)?;
    let machine_mode = mode != StdoutMode::Normal;

    let provider =
        Provider::<Http>::try_from(dep.rpc_url.as_str())?.interval(Duration::from_millis(350));

    let chain_id = provider.get_chainid().await?.as_u64();
    if chain_id != dep.chain_id {
        return Err(anyhow!(
            "chainId mismatch: deployment has {}, RPC returned {}",
            dep.chain_id,
            chain_id
        ));
    }

    let entrypoint =
        Address::from_str(&args.common.entrypoint).context("invalid --entrypoint address")?;
    let factory_addr =
        Address::from_str(&args.common.factory).context("invalid --factory address")?;

    let (wallet, owner, owner_key_path) = load_or_generate_owner(&args.common, chain_id)?;
    let owner_env_path = owner_key_path.map(|p| p.canonicalize().unwrap_or(p));

    if mode == StdoutMode::OwnerAddress {
        println!("{}", owner);
    }

    if let Some(p) = owner_env_path.as_ref() {
        match mode {
            StdoutMode::OwnerEnvPath => {
                println!("{}", p.display());
                eprintln!("generated new owner key; saved to {}", p.display());
            }
            StdoutMode::Json => {
                eprintln!("generated new owner key; saved to {}", p.display());
            }
            _ => {
                outln!(
                    machine_mode,
                    "generated new owner key; saved to {}",
                    p.display()
                );
            }
        }
    }

    let client = Arc::new(SignerMiddleware::new(provider.clone(), wallet.clone()));

    let salt = U256::from(args.common.salt);
    let (account, deployed) =
        compute_account_address(client.clone(), factory_addr, owner, salt).await?;

    if mode == StdoutMode::SmartAccountAddress {
        println!("{}", account);
    }

    if mode == StdoutMode::Json {
        let env_path = owner_env_path.as_ref().map(|p| p.display().to_string());
        let out = serde_json::json!({
            "owner": encoding::fmt_address(owner),
            "smartAccount": encoding::fmt_address(account),
            "envPath": env_path,
        });
        println!("{}", out);
    }

    outln!(
        machine_mode,
        "smartAccount: {} (deployed={})",
        account,
        deployed
    );

    let sub_id = U256::from(args.subscription_id);
    let open_sub_abi = AbiParser::default()
        .parse(&["function collect(uint256 subscriptionId) returns (uint256,uint256)"])?;
    let open_sub = Contract::new(dep.open_sub, open_sub_abi, client.clone());
    let collect_calldata = open_sub
        .method::<_, (U256, U256)>("collect", (sub_id,))?
        .calldata()
        .ok_or_else(|| anyhow!("failed to build collect calldata"))?;

    let (call_data, init_code, nonce) = build_single_call_payload(
        client.clone(),
        entrypoint,
        factory_addr,
        owner,
        salt,
        account,
        deployed,
        dep.open_sub,
        collect_calldata,
    )
    .await?;

    let tx_args: TxArgs = (&args).into();
    let _got_receipt = send_userop(
        &provider,
        client.clone(),
        &wallet,
        entrypoint,
        chain_id,
        account,
        call_data,
        init_code,
        nonce,
        &tx_args,
        machine_mode,
    )
    .await?;

    Ok(())
}

fn stdout_mode(common: &CommonArgs) -> Result<StdoutMode> {
    let mut count = 0u8;
    if common.print_owner_env_path {
        count += 1;
    }
    if common.print_owner {
        count += 1;
    }
    if common.print_smart_account {
        count += 1;
    }
    if common.json {
        count += 1;
    }

    if count > 1 {
        return Err(anyhow!(
            "--print-owner-env-path, --print-owner, --print-smart-account, and --json are mutually exclusive"
        ));
    }

    if common.print_owner_env_path {
        if !common.new_owner {
            return Err(anyhow!("--print-owner-env-path requires --new-owner"));
        }
        return Ok(StdoutMode::OwnerEnvPath);
    }

    if common.print_owner {
        return Ok(StdoutMode::OwnerAddress);
    }

    if common.print_smart_account {
        return Ok(StdoutMode::SmartAccountAddress);
    }

    if common.json {
        return Ok(StdoutMode::Json);
    }

    Ok(StdoutMode::Normal)
}

fn choose_secrets_dir() -> Result<PathBuf> {
    // Prefer the repo root `.secrets/` even if the CLI is run from a subdirectory (e.g. `aa-rs/`).
    // Heuristic: walk up a few directories looking for a `deployments/` folder or `.git/`.
    let mut dir = std::env::current_dir().context("failed to read current dir")?;

    for _ in 0..6 {
        if dir.join(".git").exists() || dir.join("deployments").is_dir() {
            return Ok(dir.join(".secrets"));
        }
        if !dir.pop() {
            break;
        }
    }

    // Fallback: cwd/.secrets
    let cwd = std::env::current_dir().context("failed to read current dir")?;
    Ok(cwd.join(".secrets"))
}

fn write_owner_env_file(path: &PathBuf, owner: Address, private_key_hex: &str) -> Result<()> {
    let contents = format!(
        "# Generated by opensub-aa --new-owner\n# DO NOT COMMIT THIS FILE.\nexport OPENSUB_AA_OWNER_PRIVATE_KEY={}\nexport OPENSUB_AA_OWNER_ADDRESS={}\n",
        private_key_hex,
        owner
    );

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).context("failed to create .secrets dir")?;
    }

    fs::write(path, contents).with_context(|| format!("failed to write {}", path.display()))?;

    // Best-effort restrictive permissions (unix).
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let perm = fs::Permissions::from_mode(0o600);
        let _ = fs::set_permissions(path, perm);
    }

    Ok(())
}

fn generate_random_wallet(chain_id: u64) -> Result<(LocalWallet, Address, String)> {
    let mut rng = OsRng;
    // Very low probability of invalid key; loop until LocalWallet accepts.
    for _ in 0..64 {
        let mut bytes = [0u8; 32];
        rng.fill_bytes(&mut bytes);
        if bytes.iter().all(|b| *b == 0) {
            continue;
        }
        let pk_hex = format!("0x{}", hex::encode(bytes));
        if let Ok(mut wallet) = LocalWallet::from_str(&pk_hex) {
            wallet = wallet.with_chain_id(chain_id);
            let owner = wallet.address();
            return Ok((wallet, owner, pk_hex));
        }
    }
    Err(anyhow!(
        "failed to generate a valid random private key after multiple attempts"
    ))
}

fn load_or_generate_owner(
    common: &CommonArgs,
    chain_id: u64,
) -> Result<(LocalWallet, Address, Option<PathBuf>)> {
    if common.new_owner {
        let (wallet, owner, pk_hex) = generate_random_wallet(chain_id)?;

        let secrets_dir = choose_secrets_dir()?;
        let fname = format!("aa_owner_{}.env", hex::encode(owner.as_bytes()));
        let path = secrets_dir.join(fname);
        write_owner_env_file(&path, owner, &pk_hex)?;
        return Ok((wallet, owner, Some(path)));
    }

    let owner_pk = common.owner_private_key.clone().ok_or_else(|| {
        anyhow!(
            "missing OPENSUB_AA_OWNER_PRIVATE_KEY (or --owner-private-key), or pass --new-owner"
        )
    })?;
    let mut wallet = LocalWallet::from_str(&owner_pk).context("invalid owner private key")?;
    wallet = wallet.with_chain_id(chain_id);
    let owner = wallet.address();
    Ok((wallet, owner, None))
}

async fn compute_account_address<M: Middleware + 'static>(
    client: Arc<M>,
    factory: Address,
    owner: Address,
    salt: U256,
) -> Result<(Address, bool)> {
    let factory_abi = AbiParser::default()
        .parse(&["function getAddress(address owner, uint256 salt) view returns (address)"])?;
    let factory = Contract::new(factory, factory_abi, client.clone());

    let account: Address = factory
        .method("getAddress", (owner, salt))?
        .call()
        .await
        .context("factory.getAddress failed")?;

    let code = client
        .get_code(account, None)
        .await
        .context("eth_getCode failed")?;

    Ok((account, !code.as_ref().is_empty()))
}

async fn read_plan<M: Middleware + 'static>(
    client: Arc<M>,
    open_sub: Address,
    plan_id: U256,
) -> Result<(Address, U256, bool)> {
    let open_sub_abi = AbiParser::default().parse(&[
        "function plans(uint256) view returns (address merchant,address token,uint256 price,uint40 interval,uint16 collectorFeeBps,bool active,uint40 createdAt)",
    ])?;
    let open_sub = Contract::new(open_sub, open_sub_abi, client);

    let (_merchant, token, price, _interval, _fee_bps, active, _created_at): (
        Address,
        Address,
        U256,
        u64,
        u16,
        bool,
        u64,
    ) = open_sub.method("plans", plan_id)?.call().await?;

    Ok((token, price, active))
}

async fn fetch_entrypoint_nonce<M: Middleware + 'static>(
    client: Arc<M>,
    entrypoint: Address,
    account: Address,
) -> Result<U256> {
    let entrypoint_abi = AbiParser::default()
        .parse(&["function getNonce(address sender, uint192 key) view returns (uint256)"])?;
    let entrypoint_c = Contract::new(entrypoint, entrypoint_abi, client.clone());

    let nonce: U256 = entrypoint_c
        .method("getNonce", (account, U256::zero()))?
        .call()
        .await
        .context("entryPoint.getNonce failed")?;
    Ok(nonce)
}

async fn build_init_code<M: Middleware + 'static>(
    client: Arc<M>,
    factory: Address,
    owner: Address,
    salt: U256,
    deployed: bool,
) -> Result<Bytes> {
    if deployed {
        return Ok(Bytes::from(Vec::new()));
    }
    let factory_abi = AbiParser::default()
        .parse(&["function createAccount(address owner, uint256 salt) returns (address)"])?;
    let factory_c = Contract::new(factory, factory_abi, client.clone());
    let create_calldata = factory_c
        .method::<_, Address>("createAccount", (owner, salt))?
        .calldata()
        .ok_or_else(|| anyhow!("failed to build createAccount calldata"))?;

    let mut v = Vec::with_capacity(20 + create_calldata.len());
    v.extend_from_slice(factory.as_bytes());
    v.extend_from_slice(create_calldata.as_ref());
    Ok(Bytes::from(v))
}

#[allow(clippy::too_many_arguments)]
async fn build_userop_payload<M: Middleware + 'static>(
    client: Arc<M>,
    entrypoint: Address,
    factory: Address,
    open_sub: Address,
    token: Address,
    plan_id: U256,
    owner: Address,
    salt: U256,
    account: Address,
    deployed: bool,
    mint_amount: Option<U256>,
    allowance_amount: U256,
) -> Result<(Bytes, Bytes, U256)> {
    let nonce = fetch_entrypoint_nonce(client.clone(), entrypoint, account).await?;
    let init_code = build_init_code(client.clone(), factory, owner, salt, deployed).await?;

    // Token call data (optionally mint, then approve).
    // NOTE: `mint` is demo-only; it will revert on real tokens.
    let token_abi = AbiParser::default().parse(&[
        "function mint(address to, uint256 amount)",
        "function approve(address spender, uint256 amount) returns (bool)",
    ])?;
    let token_c = Contract::new(token, token_abi, client.clone());

    let mint_calldata: Option<Bytes> = if let Some(amt) = mint_amount {
        Some(
            token_c
                .method::<_, ()>("mint", (account, amt))?
                .calldata()
                .ok_or_else(|| anyhow!("failed to build mint calldata"))?,
        )
    } else {
        None
    };

    let approve_calldata = token_c
        .method::<_, bool>("approve", (open_sub, allowance_amount))?
        .calldata()
        .ok_or_else(|| anyhow!("failed to build approve calldata"))?;

    let open_sub_abi =
        AbiParser::default().parse(&["function subscribe(uint256 planId) returns (uint256)"])?;
    let open_sub = Contract::new(open_sub, open_sub_abi, client.clone());
    let subscribe_calldata = open_sub
        .method::<_, U256>("subscribe", plan_id)?
        .calldata()
        .ok_or_else(|| anyhow!("failed to build subscribe calldata"))?;

    // SimpleAccount.executeBatch(address[] dest, bytes[] func)
    let account_abi =
        AbiParser::default().parse(&["function executeBatch(address[] dest, bytes[] func)"])?;
    let account_c = Contract::new(account, account_abi, client);

    let mut dests: Vec<Address> = Vec::new();
    let mut funcs: Vec<Bytes> = Vec::new();

    if let Some(m) = mint_calldata {
        dests.push(token);
        funcs.push(m);
    }

    dests.push(token);
    funcs.push(approve_calldata);

    dests.push(open_sub.address());
    funcs.push(subscribe_calldata);

    let call_data = account_c
        .method::<_, ()>("executeBatch", (dests, funcs))?
        .calldata()
        .ok_or_else(|| anyhow!("failed to build executeBatch calldata"))?;

    Ok((call_data, init_code, nonce))
}

async fn build_single_call_payload<M: Middleware + 'static>(
    client: Arc<M>,
    entrypoint: Address,
    factory: Address,
    owner: Address,
    salt: U256,
    account: Address,
    deployed: bool,
    target: Address,
    target_calldata: Bytes,
) -> Result<(Bytes, Bytes, U256)> {
    let nonce = fetch_entrypoint_nonce(client.clone(), entrypoint, account).await?;
    let init_code = build_init_code(client.clone(), factory, owner, salt, deployed).await?;

    // SimpleAccount.execute(address dest, uint256 value, bytes func)
    let account_abi = AbiParser::default()
        .parse(&["function execute(address dest, uint256 value, bytes func)"])?;
    let account_c = Contract::new(account, account_abi, client);
    let call_data = account_c
        .method::<_, ()>("execute", (target, U256::zero(), target_calldata))?
        .calldata()
        .ok_or_else(|| anyhow!("failed to build execute calldata"))?;

    Ok((call_data, init_code, nonce))
}

async fn send_userop<M: Middleware + 'static>(
    provider: &Provider<Http>,
    client: Arc<M>,
    wallet: &LocalWallet,
    entrypoint: Address,
    chain_id: u64,
    account: Address,
    call_data: Bytes,
    init_code: Bytes,
    nonce: U256,
    args: &TxArgs,
    machine_mode: bool,
) -> Result<bool> {
    // Fee data (fallback to gas price for providers without EIP-1559 helpers).
    let gas_price = provider
        .get_gas_price()
        .await
        .context("failed to fetch gas price")?;
    let bps = args.gas_multiplier_bps.max(1);
    let max_priority_fee_per_gas = gas_price * U256::from(bps) / U256::from(10_000u64);
    let max_fee_per_gas = max_priority_fee_per_gas;

    if bps != 10_000 {
        tracing::info!(
            "gas multiplier applied: {} bps (maxFeePerGas={}, maxPriorityFeePerGas={})",
            bps,
            max_fee_per_gas,
            max_priority_fee_per_gas
        );
    }

    // Initial gas guesses (will be overwritten by bundler estimate).
    let mut op = UserOperation {
        sender: account,
        nonce,
        init_code,
        call_data,
        // Use zero initial gas fields. Bundlers will fill these in `eth_estimateUserOperationGas`,
        // and paymasters (ERC-7677) can still return stub data for estimation.
        call_gas_limit: U256::zero(),
        verification_gas_limit: U256::zero(),
        pre_verification_gas: U256::zero(),
        max_fee_per_gas,
        max_priority_fee_per_gas,
        paymaster_and_data: Bytes::from(Vec::new()),
        signature: Bytes::from(vec![0u8; 65]),
    };

    let bundler = BundlerClient::new(args.bundler.clone());

    // Optional paymaster (Milestone 6B: Alchemy Gas Manager via ERC-7677).
    let (paymaster, policy_id) = if args.sponsor_gas {
        let url = args.paymaster_url.clone().ok_or_else(|| {
            anyhow!("--sponsor-gas requires --paymaster-url (or OPENSUB_AA_PAYMASTER_URL)")
        })?;
        let policy_id = args.policy_id.clone().ok_or_else(|| {
            anyhow!("--sponsor-gas requires --policy-id (or OPENSUB_AA_GAS_MANAGER_POLICY_ID)")
        })?;

        (Some(PaymasterClient::new(url)), Some(policy_id))
    } else {
        (None, None)
    };

    // If using a paymaster, fetch stub paymasterAndData BEFORE gas estimation.
    if let (Some(pm), Some(pid)) = (paymaster.as_ref(), policy_id.as_ref()) {
        outln!(
            machine_mode,
            "requesting paymaster stub data (pm_getPaymasterStubData)..."
        );
        let stub = pm
            .get_paymaster_stub_data(
                encoding::user_op_to_paymaster_json(&op),
                entrypoint,
                chain_id,
                pid,
                args.webhook_data.as_deref(),
            )
            .await
            .context("pm_getPaymasterStubData failed")?;
        op.paymaster_and_data = stub;
    }

    // Sign for estimation.
    sign_userop(client.clone(), entrypoint, &mut op, wallet).await?;

    // Estimate gas via bundler.
    let est = bundler
        .estimate_user_operation_gas(encoding::user_op_to_json(&op), entrypoint)
        .await
        .context("bundler gas estimate failed")?;

    op.call_gas_limit = est.call_gas_limit;
    op.verification_gas_limit = est.verification_gas_limit;
    op.pre_verification_gas = est.pre_verification_gas;

    // If using a paymaster, fetch FINAL paymasterAndData AFTER gas estimation.
    if let (Some(pm), Some(pid)) = (paymaster.as_ref(), policy_id.as_ref()) {
        outln!(
            machine_mode,
            "requesting paymaster final data (pm_getPaymasterData)..."
        );
        let final_pm = pm
            .get_paymaster_data(
                encoding::user_op_to_paymaster_json(&op),
                entrypoint,
                chain_id,
                pid,
                args.webhook_data.as_deref(),
            )
            .await
            .context("pm_getPaymasterData failed")?;
        op.paymaster_and_data = final_pm;
    }

    // Re-sign with final gas limits + final paymasterAndData.
    sign_userop(client.clone(), entrypoint, &mut op, wallet).await?;

    outln!(
        machine_mode,
        "\nUserOperation (final):\n{}",
        serde_json::to_string_pretty(&encoding::user_op_to_json(&op))?
    );

    if args.dry_run {
        outln!(machine_mode, "\n--dry-run set: not sending user operation.");
        return Ok(false);
    }

    // Send.
    let user_op_hash = bundler
        .send_user_operation(encoding::user_op_to_json(&op), entrypoint)
        .await
        .context("bundler send failed")?;

    outln!(
        machine_mode,
        "\nuserOpHash: {}",
        encoding::fmt_h256(user_op_hash)
    );

    if args.no_wait {
        outln!(machine_mode, "--no-wait set: not waiting for receipt.");
        return Ok(false);
    }

    let receipt = bundler
        .wait_user_operation_receipt(user_op_hash, Duration::from_secs(args.max_wait_seconds))
        .await
        .context("failed waiting for userOp receipt")?;

    outln!(
        machine_mode,
        "\nUserOp receipt:\n{}",
        serde_json::to_string_pretty(&receipt)?
    );

    Ok(true)
}

async fn sign_userop<M: Middleware + 'static>(
    client: Arc<M>,
    entrypoint: Address,
    op: &mut UserOperation,
    wallet: &LocalWallet,
) -> Result<()> {
    // Use the on-chain EntryPoint.getUserOpHash for correctness.
    let entrypoint_abi: Abi = serde_json::from_str(
        r#"[{"inputs":[{"components":[{"internalType":"address","name":"sender","type":"address"},{"internalType":"uint256","name":"nonce","type":"uint256"},{"internalType":"bytes","name":"initCode","type":"bytes"},{"internalType":"bytes","name":"callData","type":"bytes"},{"internalType":"uint256","name":"callGasLimit","type":"uint256"},{"internalType":"uint256","name":"verificationGasLimit","type":"uint256"},{"internalType":"uint256","name":"preVerificationGas","type":"uint256"},{"internalType":"uint256","name":"maxFeePerGas","type":"uint256"},{"internalType":"uint256","name":"maxPriorityFeePerGas","type":"uint256"},{"internalType":"bytes","name":"paymasterAndData","type":"bytes"},{"internalType":"bytes","name":"signature","type":"bytes"}],"internalType":"struct UserOperation","name":"userOp","type":"tuple"}],"name":"getUserOpHash","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"}]"#,
    )
    .context("failed to parse EntryPoint ABI")?;

    let entrypoint_c = Contract::new(entrypoint, entrypoint_abi, client);

    let user_op_tuple = op.as_abi_tuple();
    let user_op_hash: H256 = entrypoint_c
        .method("getUserOpHash", (user_op_tuple,))?
        .call()
        .await
        .context("entryPoint.getUserOpHash failed")?;

    let sig = wallet
        .sign_message(user_op_hash.as_bytes())
        .await
        .context("failed to sign userOpHash")?;

    op.signature = Bytes::from(sig.to_vec());

    Ok(())
}

async fn fund_account_eth<M: Middleware + 'static>(
    client: Arc<M>,
    account: Address,
    amount_wei: U256,
) -> Result<()> {
    if amount_wei.is_zero() {
        return Ok(());
    }

    let tx = TransactionRequest::new().to(account).value(amount_wei);
    let pending = client
        .send_transaction(tx, None)
        .await
        .context("failed to send ETH funding tx")?;

    let receipt = pending
        .await
        .context("failed waiting for ETH funding receipt")?;
    if receipt.is_none() {
        return Err(anyhow!("ETH funding tx dropped from mempool"));
    }

    tracing::info!("funded smart account with {} wei", amount_wei);
    Ok(())
}

async fn active_subscription_of<M: Middleware + 'static>(
    client: Arc<M>,
    open_sub: Address,
    plan_id: U256,
    subscriber: Address,
) -> Result<U256> {
    let abi = AbiParser::default().parse(&[
        "function activeSubscriptionOf(uint256 planId, address subscriber) view returns (uint256)",
    ])?;
    let open_sub = Contract::new(open_sub, abi, client);

    let sub_id: U256 = open_sub
        .method("activeSubscriptionOf", (plan_id, subscriber))?
        .call()
        .await?;

    Ok(sub_id)
}

async fn has_access<M: Middleware + 'static>(
    client: Arc<M>,
    open_sub: Address,
    subscription_id: U256,
) -> Result<bool> {
    let abi = AbiParser::default()
        .parse(&["function hasAccess(uint256 subscriptionId) view returns (bool)"])?;
    let open_sub = Contract::new(open_sub, abi, client);

    let ok: bool = open_sub
        .method("hasAccess", subscription_id)?
        .call()
        .await?;
    Ok(ok)
}
