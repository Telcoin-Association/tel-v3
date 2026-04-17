# Plamen evm/oracle-analysis — Coverage

**Checked — N/A.**

No oracles are used by any in-scope contract. No spot price, TWAP, Chainlink, or any other external price feed. Migration is fixed 1:1; bridge transfers are 1:1 in local decimals (dust-stripped).

`grep -rn "oracle\|Oracle\|IAggregator\|Chainlink\|TWAP\|priceFeed" src/` returns no hits.
