# Architecture

## Overview

Prophecy Hook is a Uniswap v4 hook that powers asset-backed prediction markets.
It combines three core contracts:

1. **PredictionHook** — the v4 hook (beforeSwap/afterSwap)
2. **SingleSidedVault** — LP deposits and payouts
3. **JITSettlementEngine** — flash-swap fallback

## Contract Diagram
