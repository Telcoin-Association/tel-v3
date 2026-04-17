# qs_skills/oracle-flashloan-analysis — Coverage

**N/A** — no oracle and no flash-loan in scope. Confirmed via search:

```
grep -rn "oracle\|Oracle\|IAggregator\|Chainlink\|TWAP\|priceFeed\|flash\|IERC3156" src/
```

Returns no hits.

Migration uses a fixed 1:1 + `1e16` decimal multiplier (compile-time constants). Bridge uses only LayerZero's delivery layer — no pricing.
