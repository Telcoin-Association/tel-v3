# Plamen evm/storage-layout-safety — Coverage

**Checked — N/A effective.**

Contracts are NOT upgradeable. No proxy, no UUPS/Transparent/Beacon, no `__gap`. Storage collision concerns do not apply.

Diamond inheritance chains (TelcoinBridge inherits MintBurnOFTAdapter → OFTCore → OApp+OAppPreCrimeSimulator+OAppOptionsType3, plus Ownable2Step → Ownable, plus Pausable) produce a flat storage layout resolved at compile time. Each storage slot is uniquely named via Solidity's linearisation; no collisions possible in a non-upgradeable deployment.
