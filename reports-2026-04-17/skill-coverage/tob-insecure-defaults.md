# trailofbits/skills — insecure-defaults — Coverage

**Checked.**

Default configuration surfaces:

- `sharedDecimals = 6` — inherited from OFTCore default; matches README. Appropriate for a token with 18 local decimals. No override in-scope.
- `decimalConversionRate = 10^(18-6) = 1e12` — consequent of sharedDecimals; dust below 1e12 is stripped from bridge amounts, documented.
- `OAppOptionsType3` — inherited. Provides the "enforced options" pattern. Owner-only configuration.
- Pausable initial state: not paused (Pausable default). Correct — bridges need to be live to function.
- DEFAULT_ADMIN_ROLE granted to `admin_` in TelcoinV3 constructor. Admin may be multisig or EOA — governance-determined.
- Ownable initial owner is `_initialOwner` / `_delegate` / `_owner` depending on contract — passed at deploy time.
- No magic defaults like "zero timelock" that would bypass governance delays (the protocol has no timelock at all — documented trade-off).
- `evm_version = "prague"` in foundry.toml — targets post-Shanghai. Matches target chain EVM versions (Ethereum Pectra, Polygon Amoy+, Base, TelcoinNetwork).
- Fuzz config: `runs = 100`, `invariant runs = 256, depth = 15`. This review's harness exceeds those numbers (Echidna 500k, Medusa 224k).

No insecure-default identified.
