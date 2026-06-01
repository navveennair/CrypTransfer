# Phase 11: Admin Dashboard Security & Efficiency Hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 11-admin-dashboard-security-efficiency-hardening-fix-critical-u
**Areas discussed:** AdminGuard implementation, TransferVolumeChart real data, ConnectionNodeMap stream consolidation

---

## AdminGuard implementation

| Option | Description | Selected |
|--------|-------------|----------|
| Route wrapper in main.dart | Replace `AdminDashboard()` in routes map with `AdminGuard(child: AdminDashboard())`. Clean separation — admin check enforced at route level. | ✓ |
| Inside AdminDashboard itself | StreamBuilder at the top of AdminDashboard that checks isAdmin before rendering tabs. No new class needed. | |

**User's choice:** Route wrapper in main.dart

| Option | Description | Selected |
|--------|-------------|----------|
| Silent redirect to home | Navigator.pop() or pushReplacementNamed. No message. | |
| Show a brief error then redirect | SnackBar('Access denied') then redirect home. | ✓ |

**User's choice:** Show SnackBar "Access denied" then redirect home

---

## TransferVolumeChart real data

| Option | Description | Selected |
|--------|-------------|----------|
| Last 7 days, grouped by day | 7 data points. Easy admin dashboard read. | ✓ |
| Last 24 hours, grouped by hour | 24 data points. More granular. | |

**User's choice:** Last 7 days, grouped by day

| Option | Description | Selected |
|--------|-------------|----------|
| In Dart from streamed docs | Filter + bucket in Dart from existing stream. 1 Firestore read. | ✓ |
| Firestore count() per day | 7 round-trips. More Firestore reads for same data. | |

**User's choice:** In Dart, group from existing streamTransferLogsDetail()

---

## ConnectionNodeMap stream consolidation

| Option | Description | Selected |
|--------|-------------|----------|
| Snapshot-on-load (FutureBuilder) | Load users + friendships once. No ongoing N streams. | ✓ |
| Real-time (1 stream + batch query) | Keep live but consolidate to 1 outer stream + 1 batch get(). | |

**User's choice:** Snapshot-on-load is fine — FutureBuilder

| Option | Description | Selected |
|--------|-------------|----------|
| Cap at 50 users | .limit(50) on users query. Bounded and predictable. | ✓ |
| No cap | Unlimited grid. | |

**User's choice:** Cap at 50 users

---

## Claude's Discretion

- Exact SnackBar duration in AdminGuard redirect
- Whether to add a "Refresh" button to ConnectionNodeMap FutureBuilder
- Y-axis padding in TransferVolumeChart
- Order of fixes within plan waves

## Deferred Ideas

- Real-time per-user connection counts in node map — snapshot-on-load accepted as sufficient for thesis
- Pagination UI with load-more button — .limit(200) cap chosen instead
- Cloud Functions for denormalized connectionCount field — over-engineered for current scale
