# Phase 8: applicationId Rename - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `08-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-05-29
**Phase:** 08-applicationid-rename-replace-com-example-cryptransfer-with-p
**Areas discussed:** New package name, MethodChannel naming, Firebase / google-services.json, Verification plan

---

## New Package Name

### Q1 — Package style

| Option | Description | Selected |
|--------|-------------|----------|
| Personal: `com.navveennair.cryptransfer` | Reverse-domain based on owner name. Indie/portfolio convention. No domain ownership required. | ✓ |
| Academic: `uk.ac.herts.cryptransfer` | Reverse-domain based on University of Hertfordshire. Signals research provenance. | |
| Product-only: `app.cryptransfer` | Short, brand-first. Requires `cryptransfer.app` domain ownership. | |
| Generic product: `com.cryptransfer.app` | Brand-first under com. No domain required. | |

**User's choice:** Personal — `com.navveennair.cryptransfer`

### Q2 — Gradle namespace vs applicationId

| Option | Description | Selected |
|--------|-------------|----------|
| Both match: `com.navveennair.cryptransfer` (Recommended) | Standard greenfield convention. R class package matches install ID. | ✓ |
| `namespace` stays `com.example.cryptransfer`, only `applicationId` changes | Postpones Kotlin file moves; leaves confusing mismatch. | |

**User's choice:** Both match.

### Q3 — iOS/macOS iosBundleId

| Option | Description | Selected |
|--------|-------------|----------|
| Update iosBundleId to `com.navveennair.cryptransfer` | Cosmetic alignment; no Android impact; keeps codebase consistent for future iOS phase. | ✓ |
| Leave as `com.example.cryptransfer` | iOS is out of scope for v1.0; defer to whenever iOS phase runs. | |

**User's choice:** Update.

---

## MethodChannel Naming

### Q1 — Stable vs package-tracking namespace

| Option | Description | Selected |
|--------|-------------|----------|
| Track package: `com.navveennair.cryptransfer/{security,file}` | Standard Flutter convention. Touches all 3 files now; touches them again on any future rename. | |
| Stable: `cryptransfer/{security,file}` (Recommended) | Decouples cross-language bridge from `applicationId`. Resolves CONCERNS.md §5 watch-list item. | ✓ |

**User's choice:** Stable.
**Notes:** Affects `MainActivity.kt` constants + KDoc, `security_lifecycle_mixin.dart:24`, `decrypt_screen.dart:52`.

---

## Firebase / google-services.json

### Q1 — Firebase project strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Add new app to `cryptransfer-96e9f`, keep old registered (Recommended) | Second Android app entry for new package. Preserves all users/audit logs/handshakes. Old entry as safety net during transition. | ✓ |
| Add new app to `cryptransfer-96e9f`, delete old | Same but immediate cleanup; loses fallback for stale builds. | |
| Create new Firebase project | Clean slate; wipes all thesis demo data. | |

**User's choice:** Add new, keep old.

---

## Verification Plan

### Q1 — On-device verification

| Option | Description | Selected |
|--------|-------------|----------|
| `flutter build apk` + on-device install + smoke test (Recommended) | Real device confirms FLAG_SECURE, kill-switch, MethodChannel rename end-to-end. | ✓ |
| `flutter build apk` only | Lower confidence; defer device test to next manual UAT. | |

**User's choice:** Full on-device smoke.

### Q2 — Coupling regression guard

| Option | Description | Selected |
|--------|-------------|----------|
| No — leave guard to future phase (Recommended) | Keeps Phase 8 focused on rename. Logged as deferred idea. | ✓ |
| Yes — add `silent_guardian.ps1` rule in this phase | Permanent fix for coupling drift; ~30 min scripting. | |

**User's choice:** Defer guard.

### Q3 — Old Kotlin directory cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Delete entire `com/example/` tree (Recommended) | Avoids dead source paths and stale `graphify-out/cache/` artifact. | ✓ |
| Leave for now | Lower-risk if search isn't exhaustive; leaves clutter. | |

**User's choice:** Delete tree.

---

## Claude's Discretion

The following were not selected during gray-area selection but the resulting defaults are documented in `08-CONTEXT.md` Implementation Decisions / Claude's Discretion:
- Order of operations across the multi-system rename
- Wave/plan partitioning
- Atomic commit grouping
- Whether to `flutter clean` between Gradle config changes
- Whether to bump `versionCode` / `versionName` (deferred)
- FileProvider authority handling (uses `${applicationId}` placeholder — auto-updates)

## Deferred Ideas

- Cross-language coupling guard scanner (`silent_guardian.ps1` rule) — `.planning/codebase/CONCERNS.md` §5
- Delete the `com.example.cryptransfer` Firebase Android app registration once stale builds are confirmed gone
- iOS / macOS Firebase setup (Xcode + `GoogleService-Info.plist`)
- `versionCode` / `versionName` bump for first Play Store submission
