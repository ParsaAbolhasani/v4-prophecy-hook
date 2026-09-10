<!-- ═══════════════════════════════════════════════════════════════════ -->
<!--                        PROPHECY HOOK README                        -->
<!-- ═══════════════════════════════════════════════════════════════════ -->

<div align="center">

# 🔮 Prophecy Hook

### A production-grade Uniswap v4 hook powering asset-backed prediction markets

**Single-sided vaults · JIT flash-swap settlement · Dynamic Pyth fees · Zero liquidation**

<br />

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?logo=solidity&logoColor=white)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-000000?logo=foundry&logoColor=white)](https://book.getfoundry.sh/)
[![Uniswap v4](https://img.shields.io/badge/Uniswap-v4-FF007A?logo=uniswap&logoColor=white)](https://docs.uniswap.org/contracts/v4/overview)
[![Pyth](https://img.shields.io/badge/Oracle-Pyth-6B46C1?logo=pyth&logoColor=white)](https://pyth.network/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-42%20passing-brightgreen)](test/)
[![Coverage](https://img.shields.io/badge/coverage-98%25-brightgreen)](test/)

<br />

[Overview](#-overview) ·
[Architecture](#-architecture) ·
[How It Works](#-how-it-works) ·
[Quick Start](#-quick-start) ·
[Testing](#-testing) ·
[Security](#-security) ·
[Roadmap](#-roadmap)

</div>

---

## 📖 Overview

Traditional prediction markets force users to **sell their assets into USD** before betting.
This exposes them to **impermanent loss**, **liquidation risk**, and **slippage** —
three problems that have kept billions of dollars of tokenized stock and memecoins
sitting on the sidelines.

**Prophecy Hook** solves this by letting users **deposit the tokens they already hold**
(`$AAPL`, `$TSLA`, `$CASHCAT`, or any ERC-20) directly into prediction rounds —
and get paid in the **same asset** if they win.

Built natively on **Uniswap v4**, the hook leverages the Singleton architecture and
Flash Accounting to deliver atomic, gas-efficient settlement without ever touching
a centralized exchange.

---

## ✨ Key Features

<table>
<tr>
<td width="50%">

### 🔒 Single-Sided Vaults
Liquidity providers deposit **one asset** — not a 50/50 pair.
No impermanent loss. Yield paid in the same token deposited.

</td>
<td width="50%">

### ⚡ JIT Flash-Swap Settlement
If the house vault is short on inventory, the protocol
atomically flash-swaps losing collateral via Uniswap v4.

</td>
</tr>
<tr>
<td width="50%">

### 📊 Dynamic Pyth-Driven Fees
House edge scales from **2% → 5%** based on realized
volatility, protecting LPs during turbulent markets.

</td>
<td width="50%">

### 🛡️ Principal Protection
On a win or break-even, **100% of principal** is returned.
Users only ever risk their wagered amount.

</td>
</tr>
<tr>
<td width="50%">

### 🔄 Buyback & Burn Routing
Losing collateral is routed to the protocol's
buyback-and-burn module, aligning incentives.

</td>
<td width="50%">

### ⏳ Transient Liquidity
Locked collateral **earns Uniswap swap fees** in the
background throughout the round duration.

</td>
</tr>
</table>

---

## 🏗️ Architecture



### Contract Layout

| Contract | Responsibility |
|----------|----------------|
| `PredictionHook.sol` | Core v4 hook — `beforeSwap`, `afterSwap`, dynamic fees, round lifecycle |
| `SingleSidedVault.sol` | LP deposits, share accounting, direct payouts, yield distribution |
| `JITSettlementEngine.sol` | Flash-swap orchestration, oracle rate lookup, fair-value fallback |
| `PredictionMarket.sol` | Round state machine, victory metric, settlement trigger |
| `SettlementMath.sol` | Pure math — payout computation, fee scaling, volatility proxy |

---

## 🔄 How It Works

### Lifecycle of a Prediction Round

mermaid
sequenceDiagram
    participant U as User
    participant H as ProphecyHook
    participant V as SingleSidedVault
    participant P as Pyth Oracle
    participant PM as PoolManager

    U->>H: openRound(poolKey, duration, collateral)
    H->>H: Store Round{startTime, endTime, collateral}

    Note over H,PM: Round is ACTIVE — swaps occur
    U->>H: swap() with collateral
    H->>P: getPrice(priceFeedId)
    P-->>H: (price, publishTime, conf)
    H->>H: computeDynamicFee(volatility)
    H->>PM: Execute swap with dynamic fee
    H->>H: Accrue transient liquidity

    Note over H,PM: Round EXPIRES — settlement triggered
    U->>H: swap() (triggers afterSwap)
    H->>V: balanceOf(asset)
    alt Vault has inventory
        V->>U: Direct payout (same asset)
    else Vault is short
        H->>V: jitSettle(assetIn, assetOut, amount)
        V->>PM: Flash swap via Uniswap v4
        PM-->>U: Converted payout (USDC / asset)
    end
    H->>H: Route losing collateral → buyback & burn


Step-by-Step
Round opens — openRound() locks collateral and starts the timer.

beforeSwap fires — Pyth oracle is queried; confidence interval checked;
dynamic fee is computed from realized volatility.

Swap executes — user's prediction is placed with the correct house edge.

afterSwap (active) — collateral accrues transient liquidity (earns Uniswap fees).

Round expires — next swap triggers settlement:

Path A: Vault has inventory → direct payout in same asset.

Path B: Vault is short → JIT flash swap converts losing collateral.

Path C: Market too thin → fair-value fallback in USDC / blue-chip.

Buyback & burn — losing collateral routed to $PROPHECY buyback module.

Prerequisites
Tool	Version	Install
Foundry	latest	book.getfoundry.sh
Node.js	≥ 18	nodejs.org
Git	≥ 2.30	git-scm.com


# 1. Clone the repository
git clone https://github.com/<your-username>/v4-prophecy-hook.git
cd v4-prophecy-hook

# 2. Install dependencies
forge install

# 3. Copy environment template
cp .env.example .env

# 4. Edit .env with your RPC and API keys

# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run a specific test suite
forge test --match-contract PredictionHookTest

# Run fork tests (requires MAINNET_RPC_URL in .env)
forge test --fork-url $MAINNET_RPC_URL --match-path "test/Fork.t.sol"


# Local (Anvil)
anvil &
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Testnet (Sepolia)
forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify

  🧪 Testing
The test suite covers every hook path and is organized by concern:
test/
├── PredictionHook.t.sol        # Hook permissions, beforeSwap, afterSwap
├── SingleSidedVault.t.sol      # Deposit, share math, payout, yield
├── JITSettlement.t.sol         # Flash-swap fallback, oracle integration
├── SettlementMath.t.sol        # Pure math fuzzing (invariant tests)
├── RoundLifecycle.t.sol        # openRound → settle → buyback
└── Fork.t.sol                  # End-to-end on a mainnet fork

Test Results
Ran 42 tests for test/PredictionHook.t.sol:PredictionHookTest
[PASS] test_BeforeSwap_RejectsStaleOracle
[PASS] test_BeforeSwap_RejectsLowConfidence
[PASS] test_BeforeSwap_ComputesDynamicFee
[PASS] test_BeforeSwap_CapsFeeAtMaximum
[PASS] test_AfterSwap_AccruesTransientLiquidity
[PASS] test_AfterSwap_SettlesExpiredRound
[PASS] test_AfterSwap_DirectPayoutWhenVaultHasInventory
[PASS] test_AfterSwap_JITFallbackWhenVaultShort
[PASS] test_AfterSwap_FairValueFallbackWhenMarketThin
[PASS] test_OpenRound_RevertsIfActive
[PASS] test_OpenRound_EmitsEvent
... (31 more)

Suite result: ok. 42 passed; 0 failed; 0 skipped


Fuzz & Invariant Tests
# Fuzz test payout math
forge test --match-test testFuzz_PayoutNeverExceedsCollateral

# Invariant: vault solvency
forge test --match-test invariant_VaultSolvency

Audit Status
⚠️ This code is unaudited. Do not deploy to mainnet with real funds
without a professional security review.

Mitigations in Place
Risk	Mitigation
Reentrancy	ReentrancyGuard on all vault entry points
Oracle staleness	60-second max age check on Pyth prices
Oracle manipulation	Confidence interval threshold (< 1% deviation)
Slippage on JIT	minAmountOut enforced on flash swaps
Vault insolvency	Inventory check before payout; JIT fallback
Round griefing	Only initiator can open; keeper can force-settle after timeout
Access control	onlyHook modifier on vault settlement functions


Known Limitations
Pyth price feeds must be validated per asset before mainnet deployment.

Volatility proxy uses a simplified EMA — production should use Pyth's TWAP.

Buyback-and-burn module is a placeholder in this MVP.

See docs/security.md for the full threat model.

🛠️ Tech Stack
<div align="center">
Layer	Technology
Language	Solidity 0.8.24
Framework	Foundry (forge, cast, anvil)
AMM	Uniswap v4-core + v4-periphery
Oracle	Pyth Network
Libraries	OpenZeppelin Contracts
CI/CD	GitHub Actions
Linting	Solhint + Forge fmt
</div>

📂 Project Structure
v4-prophecy-hook/
│
├── src/
│   ├── PredictionHook.sol           # 🔮 Core v4 hook
│   ├── SingleSidedVault.sol         # 🔒 LP vault
│   ├── JITSettlementEngine.sol      # ⚡ Flash-swap settlement
│   ├── PredictionMarket.sol         # 🎯 Round state machine
│   ├── interfaces/
│   │   ├── IPredictionHook.sol
│   │   ├── ISingleSidedVault.sol
│   │   └── IPythOracle.sol
│   └── libraries/
│       ├── HookPermissions.sol
│       └── SettlementMath.sol
│
├── test/
│   ├── PredictionHook.t.sol
│   ├── SingleSidedVault.t.sol
│   ├── JITSettlement.t.sol
│   ├── SettlementMath.t.sol
│   ├── RoundLifecycle.t.sol
│   └── Fork.t.sol
│
├── script/
│   ├── Deploy.s.sol
│   └── ConfigureHook.s.sol
│
├── docs/
│   ├── architecture.md
│   ├── flow.md
│   └── security.md
│
├── .github/
│   └── workflows/
│       └── test.yml
│
├── foundry.toml
├── remappings.txt
├── .env.example
├── .gitignore
├── Makefile
├── LICENSE
└── README.md


🗺️ Roadmap
☑ v0.1 — Core hook (beforeSwap / afterSwap)
☑ v0.2 — Single-sided vault + share accounting
☑ v0.3 — JIT settlement engine + Pyth integration
☑ v0.4 — Dynamic fee model
□ v0.5 — 0DTE micro-rounds (5min–1hr)
□ v0.6 — Multi-asset "Last Man Standing" royale
□ v0.7 — KOL leaderboard integration (off-chain oracle relay)
□ v1.0 — External audit + mainnet deployment


🤝 Contributing
Contributions are welcome! Please follow these steps:
Fork the repository
Create a feature branch (git checkout -b feature/amazing-feature)
Commit your changes (git commit -m 'Add amazing feature')
Push to the branch (git push origin feature/amazing-feature)
Open a Pull Request
Please read CONTRIBUTING.md for details on our code of conduct.


📝 License
This project is licensed under the MIT License — see the LICENSE file for details.

👤 Author
<div align="center">
Parsa Abolhasani Rad
Senior Blockchain Engineer

⭐ If this project helped you, please give it a star!
Built with ❤️ for the Uniswap v4 ecosystem


