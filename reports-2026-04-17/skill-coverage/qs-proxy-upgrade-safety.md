# qs_skills/proxy-upgrade-safety — Coverage

**Checked — N/A.**

Contracts are deployed directly (not behind a proxy). No `initialize()` function, no `__gap`, no UUPSUpgradeable / TransparentProxy usage. Storage layout safety concerns do not apply to non-upgradeable deployments.

`grep -rn "upgradeable\|UUPS\|TransparentProxy\|initialize\|_initialized\|__gap" src/` returns no hits.
