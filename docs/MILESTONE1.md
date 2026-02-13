# OpenSub — Milestone 1 (Market Research + Product Definition)

This document completes **Milestone 1** for OpenSub:

1) Clear problem + target user definition
2) Market tailwinds + supporting data
3) Competitive landscape + positioning
4) Product requirements + non-goals
5) Validation plan + success metrics

OpenSub’s Milestone 2+3 deliverables (protocol + tests) live elsewhere in this repo.

---

## One‑liner

**OpenSub is an open-source, on-chain subscription primitive for stablecoins (USDC-like ERC20s):** merchants define plans; subscribers authorize recurring charges; and any “collector” can execute renewals—without the contract custoding funds during collection.

---

## Problem

Recurring payments are a “default” business model for SaaS, APIs, content memberships, and many creator businesses. But on-chain, recurring payments run into practical friction:

- **Manual signing**: typical wallet flows require users to sign each payment transaction. Stripe explicitly calls this out as a fundamental limitation for blockchain-based subscriptions and says they built a smart contract to avoid re-signing each cycle. (Stripe blog, 2025) [1]
- **Gas + UX**: users need gas and correct tokens on the right chain, which is an adoption killer for mainstream checkout.
- **Operational reliability**: recurring charges require reliable scheduling/automation or incentives for third parties to execute “collection.”
- **Safety**: allowing “set-and-forget” token approvals introduces risk; protocols need to minimize trust assumptions and reduce accidental edge-case double charges.

OpenSub focuses on a narrow wedge: **simple, auditable, discrete billing cycles** (monthly/weekly/etc), suitable for stablecoin-denominated subscriptions.

---

## Who this is for

### Primary users

**Merchants (B2B / B2C)**
- Web3 SaaS (developer tools, analytics, infra dashboards)
- API keys / paywalled endpoints
- Communities / memberships / newsletters
- Cross-border services where cards are expensive or unreliable

**Subscribers**
- Users who already hold stablecoins
- Users in countries where card rails are limited or FX fees are high
- Users paying for digital services that don’t need chargebacks

### Secondary users
- Wallet teams / smart account teams needing a reference recurring-payments primitive
- Automation/keeper networks (Gelato-like) that can trigger renewals [7]

---

## Why now (market tailwinds)

OpenSub is intentionally aligned with the direction of major payment and infrastructure players:

### Stablecoins are being productized for mainstream commerce

- **Shopify + Stripe** announced that Shopify merchants across **34 countries** would be able to accept **USDC** on **Base** using existing checkout flows, with merchants receiving local currency by default or USDC to a wallet. (Stripe newsroom + Shopify newsroom, June 12, 2025) [2] [3]
- **Stripe** launched “stablecoin payments for subscriptions,” stating they built a smart contract so customers can authorize recurring payments without re-signing each transaction, and initially support **USDC on Base and Polygon**. [1]

### Institutions are treating stablecoins like a settlement rail

- **Visa** announced USDC settlement in the U.S. (Dec 16, 2025) and reported monthly stablecoin settlement volume passing a **$3.5B annualized run rate** as of Nov 30. [4]

### Account abstraction adoption makes “wallet UX upgrades” plausible

- Ethereum.org reports the ERC‑4337 EntryPoint has facilitated creation of **26M+ smart wallets** and **170M+ UserOperations**. That is strong evidence that “smart account UX” (gas sponsorship, batch actions, etc.) is no longer theoretical. [5]

### Regulation is becoming clearer (but also adds constraints)

- The U.S. **GENIUS Act (S.1582)** creates a federal framework for payment stablecoins (Congress CRS overview updated July 18, 2025). This may accelerate adoption but also creates requirements for issuers and service providers. [6]

OpenSub stays narrowly focused: it is a protocol primitive (software), not an issuer, not a custodian, and not a compliance product.

---

## Market reality check (important nuance)

“Stablecoin volume” is often overstated because a large share is exchange/DeFi/trading-related.

- McKinsey notes stablecoins’ transaction volume has risen sharply and references data showing annual stablecoin transaction volume exceeding **$27T/year**, while also emphasizing stablecoins process **less than 1%** of global daily money transfer volume. [8]
- Artemis research highlights how filtering can reduce raw monthly stablecoin volume (e.g., “total transaction volume”) down to a lower “adjusted” estimate, and that retail-sized flows are much smaller. [9]

This is why OpenSub’s wedge is not “stablecoins are already the global payments default.” The wedge is:

1) there is growing demand for stablecoin-based checkout (Shopify/Stripe), and
2) recurring billing is a high-value, high-frequency payments pattern where UX + automation matter.

---

## Competitive landscape (and what OpenSub is / is not)

OpenSub’s goal is **not** to “out-Stripe Stripe.” Stripe validates the demand, and OpenSub complements by being open-source and composable.

| Category | Example(s) | What they do well | Where OpenSub differs |
|---|---|---|---|
| Web2 billing with stablecoin support | Stripe stablecoin subscriptions | UX, compliance, merchant tooling; Stripe says it built a smart contract to avoid re-signing; supports USDC on Base/Polygon initially [1] | OpenSub is open-source + composable; deploy anywhere; permissionless collector model; minimal surface area |
| Commerce checkout rails | Shopify USDC on Base (with Stripe/Coinbase) | Huge distribution + familiar checkout flow [2][3] | OpenSub is a protocol building block; you bring your own frontend + fulfillment |
| Streaming payments (continuous) | Superfluid | By-the-second streaming cashflows [10] | OpenSub is discrete cycle billing (e.g., monthly) using standard ERC20s (no super-token requirements) |
| Token streaming/distribution | Sablier | Payroll/vesting/streams across many chains [11] | OpenSub focuses on recurring “subscription charge” semantics + merchant billing model |
| Automation networks | Gelato | Reliable contract automation; explicitly lists periodic payments as a scenario [7] | OpenSub works without a single automation provider (anyone can collect), but can integrate |
| Approval management | Permit2 (Uniswap Labs) | Better approval UX + shared approvals [12] | OpenSub doesn’t require Permit2; it’s an optional future enhancement |

**Key positioning statement:**

> OpenSub is a minimal, auditable, on-chain “subscription charge primitive” for stablecoins.
> It is intentionally simple enough to be reviewed and tested thoroughly, and composable enough to be used by wallets, merchant apps, or automation providers.

---

## Product requirements (Milestone 2)

OpenSub’s MVP requirements are:

### Core protocol
- Merchants can create plans: `(token, price, interval, collectorFeeBps)`
- Subscribers can subscribe; first charge happens immediately
- Subscribers can cancel immediately, or disable auto-renew while keeping access until end of the current paid period (**Pattern A**)
- Anyone can collect a due renewal (keeperless), earning an optional collector fee

### Safety constraints
- No custody during collection (direct transferFrom to merchant/collector)
- No double-charge footguns via resubscribe behavior (see `docs/SPEC.md`)
- Hardened against common ERC20 failure modes (revert, return false)
- NonReentrant + CEI for renewal flow

### Observability
- Emit events that allow indexing revenue and subscription state without heavy on-chain reads

---

## Non-goals (Milestone 1–3)

- Chargebacks / disputes / refunds
- KYC/AML, compliance UX, invoicing, tax, dunning emails
- Fiat off-ramps or settlement
- Streaming-by-the-second primitives (use Superfluid/Sablier)
- Handling fee-on-transfer or rebasing tokens as a first-class target

---

## Validation plan (how you prove this is worth building)

To complete Milestone 1 in a founder-like way, you should also run lightweight validation:

### 1) Merchant interviews (10–20)
Target:
- crypto-native SaaS
- creator tools
- cross-border services

Questions:
- Would you accept USDC on Base for subscriptions today?
- If yes, what blocks you? (UX, accounting, custody, volatility, churn)
- If no, what would need to change? (regulation, wallet UX, customer demand)

### 2) Integration prototype
- A demo “API key subscription” app using OpenSub events to gate access.

### 3) Success metrics (early)
- Time-to-integrate (goal: < 1 day for a Solidity+frontend dev)
- # of external contributors
- # of deployed testnet instances
- # of paying subscriptions in a pilot

---

## References

[1] Stripe — “Introducing stablecoin payments for subscriptions” (smart contract for recurring payments; USDC on Base/Polygon; 400+ wallets). https://stripe.com/blog/introducing-stablecoin-payments-for-subscriptions

[2] Stripe newsroom — “Stripe will help millions of Shopify merchants to accept stablecoin payments” (USDC; 34 countries; Base). https://stripe.com/newsroom/news/shopify-stripe-stablecoin-payments

[3] Shopify newsroom — “Introducing USDC on Shopify” (USDC on Base; early access; checkout flow). https://www.shopify.com/news/stablecoins-on-shopify

[4] Visa press release — “Visa Launches Stablecoin Settlement in the United States” (USDC; $3.5B annualized run rate; U.S. institutions; 7-day settlement). https://corporate.visa.com/en/sites/visa-perspectives/newsroom/visa-launches-stablecoin-settlement-in-the-united-states.html

[5] Ethereum.org — Account abstraction roadmap (ERC‑4337 EntryPoint deployed March 1, 2023; 26M+ smart wallets; 170M+ UserOperations). https://ethereum.org/roadmap/account-abstraction/

[6] Congress.gov (CRS) — “Stablecoin Legislation: An Overview of S. 1582, GENIUS Act of 2025” (updated July 18, 2025). https://www.congress.gov/crs-product/IN12553

[7] Gelato docs — “Automated Transactions” (periodic payments listed as a scenario). https://docs.gelato.cloud/web3-services/web3-functions/understanding-web3-functions/automated-transactions

[8] McKinsey — “The stable door opens: how tokenized cash enables next-gen payments” (discusses stablecoin transaction volume and payments adoption). https://www.mckinsey.com/industries/financial-services/our-insights/the-stable-door-opens-how-tokenized-cash-enables-next-gen-payments

[9] Artemis Analytics — “An empirical analysis of stablecoin payment usage on Ethereum” (adjusted vs raw stablecoin volumes; payments estimation). https://www.artemisanalytics.com/resources/an-empirical-analysis-of-stablecoin-payment-usage-on-ethereum

[10] Superfluid docs — Constant Flow Agreement (money streaming). https://superfluid.gitbook.io/superfluid/developers/constant-flow-agreement-cfa

[11] Sablier — protocol overview (token distribution, payroll/vesting). https://sablier.com/

[12] Uniswap Labs support — “What is a Permit2 approval?” https://support.uniswap.org/hc/en-us/articles/39683402190733-What-is-a-Permit2-approval
