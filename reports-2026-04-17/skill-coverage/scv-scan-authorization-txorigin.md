# kadenzipfel/scv-scan#authorization-txorigin — Coverage

**Checked — not vulnerable because:**

`grep -rn "tx.origin" src/` returns no hits. All access control uses `msg.sender` via `onlyOwner` / `onlyRole` / `onlyBridge` modifiers.
