# Security Considerations

## Threat Model

### 1. Oracle Manipulation

**Risk:** Attacker manipulates Pyth price feed to trigger favorable settlement.

**Mitigation:**
- Confidence interval check (`CONFIDENCE_THRESHOLD_BPS = 100`)
- Staleness check (`MAX_ORACLE_AGE = 60` seconds)
- Use `getPriceNoOlderThan` for on-chain verification

### 2. Reentrancy

**Risk:** Malicious token or caller re-enters vault during payout.

**Mitigation:**
- `ReentrancyGuard` on `deposit()`, `withdraw()`, `payout()`, `jitSettle()`
- Checks-Effects-Interactions pattern

### 3. Vault Insolvency

**Risk:** Vault runs out of inventory during payout.

**Mitigation:**
- `InsufficientInventory` revert if balance < payout
- JIT fallback via `jitSettle()`
- Fair-value fallback in USDC/blue-chip

### 4. Flash Swap Slippage

**Risk:** JIT swap executes at unfavorable rate.

**Mitigation:**
- `minAmountOut` parameter on swaps
- Pyth spot rate validation

### 5. Round Griefing

**Risk:** Malicious user opens rounds repeatedly to block others.

**Mitigation:**
- One active round per pool
- Keeper can force-settle after timeout

### 6. Dynamic Fee Manipulation

**Risk:** Attacker manipulates volatility to get favorable fees.

**Mitigation:**
- Fee capped at `MAX_HOUSE_EDGE_BPS = 500` (5%)
- Base fee floor at `BASE_HOUSE_EDGE_BPS = 200` (2%)

## Known Limitations

1. **Pyth price feeds must be validated per asset** before mainnet deployment.
2. **Volatility proxy uses simplified EMA** — production should use Pyth TWAP.
3. **Buyback-and-burn module is a placeholder** in this MVP.
4. **No access control on `setRouter()`** — production needs `Ownable`.

## Audit Checklist

- [ ] External audit by reputable firm
- [ ] Formal verification of settlement math
- [ ] Stress test with historical volatility data
- [ ] Bug bounty program
