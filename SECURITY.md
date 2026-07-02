# Security Policy

## Reporting a Vulnerability

The Telcoin team takes security vulnerabilities in the Telcoin V3 token and bridge contracts seriously. If you believe you have found a security vulnerability in the contracts in this repository, please report it to us privately.

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to:
- security@telcoin.org

Please include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Technical details and proof of concept if possible

## Response Process

1. We will acknowledge receipt of your report within 48 hours
2. We will provide an initial assessment of the report within 5 business days
3. We will keep you informed of our progress as we investigate and resolve the issue
4. Once resolved, we will notify you and discuss public disclosure timing

## Scope

The following contracts in this repository are in scope:

- `src/TelcoinV3.sol` — ERC-20 TEL (18 decimals); role-based mint/burn, pausable transfers, EIP-2612 permit, EIP-3009 `transferWithAuthorization`, EIP-1271 support, and `rescueBurn`.
- `src/TelcoinBridge.sol` — LayerZero V2 `MintBurnOFTAdapter` bridge for satellite chains (mint/burn ERC-20 TEL).
- `src/NativeBridge.sol` — LayerZero V2 `NativeOFTAdapter` bridge on Telcoin Network (lock/credit native TEL).
- `src/MintBurnWrapper.sol` — adapts `TelcoinV3` mint/burn to `IMintableBurnable`; holds the MINTER/BURNER roles for the active bridge.
- `src/MigrationVault.sol` — Phase 2 one-way, UUPS-upgradeable vault performing 1:1 OLD→NEW swaps.
- `src/TokenMigration.sol` — Phase 1 mint-based escrow migration (2→18 decimals, 1:1).
- `src/helpers/` — `EIP3009.sol`, `Roles.sol`.
- `src/interfaces/` — `IEIP3009.sol`, `IERC20Mintable.sol`, `ITelcoinBridge.sol`.

### Out of Scope

- Dependencies (e.g. OpenZeppelin, LayerZero) — report these to the dependency maintainer
- Deployment and test scripts
- Third-party forks and non-official integrations
- Already reported vulnerabilities
- Theoretical vulnerabilities without proof of concept
- Social engineering attacks

## Disclosure Policy

- All vulnerability reports and associated communications are considered confidential.
- We kindly ask that you **not publicly disclose** any details related to the vulnerability without our express written permission.
- We aim to fix critical vulnerabilities as quickly as possible.
- If you wish to receive credit for a valid vulnerability report, let us know, and we can discuss private recognition or other acknowledgments.
- We may provide pre-disclosure to key partners, exchanges, and integrators to protect user funds while a fix is being coordinated.

## Supported Versions

The latest deployed version of the contracts, corresponding to the current `main` branch, is supported. Security fixes are applied to this version.

## Security Updates

Security fixes are released as promptly as possible.

## Bug Bounty

There is no bug bounty program at this time.
We nonetheless welcome responsible disclosure — if you have found an issue, please email security@telcoin.org.

## Credits & Acknowledgments

We thank all security researchers who responsibly disclose vulnerabilities.
Their support is critical to keeping our contracts safe for the community.
