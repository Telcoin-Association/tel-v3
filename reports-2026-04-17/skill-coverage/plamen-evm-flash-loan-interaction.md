# Plamen evm/flash-loan-interaction — Coverage

**Checked — N/A.**

No flash-loan provider or receiver interface in scope. The migration is balance-based (`oldToken.balanceOf(msg.sender)`) which cannot be inflated atomically — OldToken is a standard ERC-20 with no flash-mint capability. The bridge's `send` consumes user's burned supply via approval + `_spendAllowance`; no loan semantics.

No fee-on-transfer, no rebasing, no flash-mint in OldToken (legacy Telcoin V2, src/legacy/Telcoin.sol).
