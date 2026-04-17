# kadenzipfel/scv-scan#insufficient-access-control — Coverage

**Checked — not vulnerable because:** every privileged path is gated.

| Function | File:line | Gate |
|---|---|---|
| TelcoinV3.mint | TelcoinV3.sol:46 | onlyRole(MINTER_ROLE) |
| TelcoinV3.burn | TelcoinV3.sol:58 | onlyRole(BURNER_ROLE) + allowance check |
| TelcoinV3.rescueBurn | TelcoinV3.sol:70 | onlyRole(DEFAULT_ADMIN_ROLE) |
| TelcoinV3.pause | TelcoinV3.sol:75 | onlyRole(PAUSER_ROLE) |
| TelcoinV3.unpause | TelcoinV3.sol:80 | onlyRole(UNPAUSER_ROLE) |
| TelcoinV3.rescueTokens | TelcoinV3.sol:85 | onlyRole(DEFAULT_ADMIN_ROLE) |
| TokenMigration.migrate | TokenMigration.sol:73 | public (by design — anyone migrates own balance) |
| TokenMigration.setMigrationExpiry | TokenMigration.sol:96 | onlyOwner |
| TokenMigration.recoverERC20 | TokenMigration.sol:109 | onlyOwner |
| TokenMigration.pause | TokenMigration.sol:127 | onlyOwner |
| TokenMigration.unpause | TokenMigration.sol:134 | onlyOwner |
| MintBurnWrapper.mint/burn | MintBurnWrapper.sol:70,82 | onlyBridge |
| MintBurnWrapper.authorizeBridge | MintBurnWrapper.sol:95 | onlyOwner (**L-01: doesn't enforce revoke-first**) |
| MintBurnWrapper.revokeBridge | MintBurnWrapper.sol:108 | onlyOwner |
| TelcoinBridge.send | TelcoinBridge.sol:72 | whenNotPaused (public send is intentional) |
| TelcoinBridge._lzReceive | TelcoinBridge.sol:83 | whenNotPaused + endpoint+peer check inherited |
| TelcoinBridge.rescueTokens | TelcoinBridge.sol:98 | onlyOwner |
| TelcoinBridge.pause/unpause | TelcoinBridge.sol:104,106 | onlyOwner |
| NativeBridge — mirrors TelcoinBridge | NativeBridge.sol | same |
