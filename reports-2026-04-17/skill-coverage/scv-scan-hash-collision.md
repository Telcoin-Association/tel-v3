# kadenzipfel/scv-scan#hash-collision — Coverage

**Checked — not vulnerable because:**

The only hash usages are `keccak256("MINTER_ROLE")` etc. (src/helpers/Roles.sol) with fixed single-string inputs — no attacker-controlled variable-length concatenation passed to `abi.encodePacked`. No `keccak256(abi.encodePacked(a, b))` pattern.
