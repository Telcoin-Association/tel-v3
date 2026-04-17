# Archethect/sc-auditor — entitlement-drift — Coverage

Role entitlements audited:

- No role can grant itself (OZ AccessControl enforces `getRoleAdmin`).
- `DEFAULT_ADMIN_ROLE` is the admin of MINTER/BURNER/PAUSER/UNPAUSER (OZ default).
- `renounceRole` disabled — no accidental self-drift.
- Wrapper holds MINTER+BURNER — known entitlement by design.
- Migration holds MINTER — scoped entitlement, expected to be revoked post-expiry.
- Bridge holds no direct TelcoinV3 role — intentional decoupling.

No drifted entitlements. All role grants are documented and auditable via AccessControlEnumerable.
