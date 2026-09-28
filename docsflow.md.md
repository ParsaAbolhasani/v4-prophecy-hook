# Settlement Flow

## Overview

This document details the complete lifecycle of a prediction round,
from opening to settlement, including all fallback paths.

## High-Level Flow

```mermaid
flowchart TD
    A[User opens round] --> B[openRound called]
    B --> C[Round stored with startTime, endTime]
    C --> D{Round active?}
    D -->|Yes| E[Users place predictions via swap]
    E --> F[beforeSwap: Pyth oracle check]
    F --> G[Dynamic fee computed]
    G --> H[afterSwap: collateral accrued]
    H --> D
    D -->|No, expired| I[Next swap triggers settlement]
    I --> J{Vault has inventory?}
    J -->|Yes| K[Direct payout in same asset]
    J -->|No| L[JIT flash swap]
    L --> M{Market liquid enough?}
    M -->|Yes| N[Convert via Uniswap v4]
    M -->|No| O[Fair-value fallback in USDC]
    K --> P[Route losing collateral to buyback]
    N --> P
    O --> P
    P --> Q[Round settled event emitted]