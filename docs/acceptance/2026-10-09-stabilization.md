# SDD ledger — plan: docs/superpowers/plans/2026-10-09-crosslink-stabilization.md

Ruling: Use existing /home/CrossLink on feat/mvp, no new worktree — user explicitly fixes SSH development location and this is an isolated project feature branch — cost: running source and checkout share a directory; verify candidates before service restart.
Ruling: Plan sections use S1-S5 rather than Task N; task briefs are exact section extracts and task completion is recorded here with command/commit/evidence — avoids changing approved plan solely for script parser — cost: manual ledger must remain accurate.
Pre-flight: S1 owns Android snapshot/owner/state, S3 consumes background event handling; preserve owner filtering and state revisions. S2 reload consumes S3 reconnect history refresh; every refresh must reject stale session results. S4 cleanup runs in another thread; lock upload registry during deletion decisions. S5 preserves array REST shape; before-only compatibility retained.
Tasks S1-S5 pending; later roadmap C4 has priority.

Task 1 S1: in progress, base e852c4a7b6d061c21b90f4efd52f400244173952
Task 1: RED original UI state failure, expanded connected/reconnecting cases failed. Native RED unresolved connectionSnapshot confirms missing native contract.
Task 1: Ruling: query backgroundSnapshot once after owner acceptance — closes initial-start event-before-owner race; snapshot revision prevents older replies from overwriting new events — cost: one extra platform call per attach.
Windows environment: user first had no node, then explicitly authorized local PC. Local Git and VS installer found, no C++ workload detected. Local build directory will be constrained to D:/aliyun/CrossLink/.build.
Task 1: complete (commit 6a55ebf401f25b4dd310737005e51d7857b293df, Dart full suite 16/16; analyzer clean; native 8/8, fresh XML 2026-10-09T06:20:24.629Z). RED→GREEN original attach, reconnecting and initial-owner race.
Task 1: Ruling: native logout test observes session.updated specifically, not every state event — new stopped event is required UI behavior; no late credential publication remains tested.
Task 2 S2: in progress, base 6a55ebf401f25b4dd310737005e51d7857b293df
Task 2 RED: API rename reverted after sign-in; Dart current name remained old; delayed reload repopulated logged-out devices. All failures observed.
Task 2: complete (commit de15c0a83668e9728dc3fa9bfb21bd24fe7254af, backend full suite 32/32; Dart full suite 18/18; analyzer clean). Covers remote rename, revoked device re-sign-in and late logged-out reload.
Task 3 S3: in progress, base de15c0a83668e9728dc3fa9bfb21bd24fe7254af
Task 3 RED: REST/WS receipt publication missing; Android/Windows sender caches stayed pending; late ACK revived logged-out history; stale history regressed read→pending. All observed.
Task 3 Ruling: merge monotonic statuses in cache.put as well as receipt events — delayed REST snapshots otherwise undo a new read event — cost: statuses cannot regress without explicit history reset.
Task 3: complete (commit f178337370d7cfd60184f46d2abb5ff222cee77a, backend full suite 34/34; Dart 22/22; analyzer clean; isolated PostgreSQL + verified HTTPS/WSS smoke includes sender delivered/read events).
Task 4 S4: in progress, base f178337370d7cfd60184f46d2abb5ff222cee77a
Task 4 RED: old orphan and actual os._exit(77) precommit orphan remained; partial symlink was incorrectly removed. Existing in-flight upload preservation passed as a required non-regression boundary.
Task 4: complete (commit 9b561c379d24d3a70280fde5748f290f7099ed15, backend full suite 38/38). Actual precommit os._exit child recovery, active final upload, retained references/recent orphan and symlinks verified.
Task 5 S5: in progress, base 9b561c379d24d3a70280fde5748f290f7099ed15
Local Windows toolchain installation explicitly authorized; verified Microsoft bootstrapper launched with UAC, no restart and no package cache.
Task 5 RED: same-second page 2 empty; invalid/missing timestamp cursors returned 200; full account traversal lost three records. Four failures observed.
Task 5: complete (commit 7252122b416fbb7f9472a5e5c3b1304de23f4c44, backend full suite 42/42; composite cursor across all same-second records, 422 malformed cursor, cross-account traversal). Candidate PostgreSQL/HTTPS/WSS verifies sender receipts, preserved names, stable cursor, file hash and revocation.
Final stabilization review pending. Production service has not reloaded source changes yet.
Final review: three Important/P2 findings verified, four regression tests RED. Fix pass: bounded session receipt buffer; own copy preserves remote status; shared device fetch revision.
Final Ruling: migrate legacy cached outgoing read to unknown until authoritative history confirms it — previous client could fabricate read, monotonic merge would preserve it forever — cost: offline legacy send states temporarily require confirmation.
Final Ruling: reviewers set aside C4, 100-entry UI, before-only compatibility, multi-worker cases and install/public acceptance — these are explicit phased limits, not fulfilled deliverables; retain them in roadmap and report. No deferred minors.
Final: fixed early receipt race, own-copy false read and device refresh order — controller_review_regression_test four RED→GREEN cases; full Dart suite 26/26, analyzer clean. Backend unchanged from verified 42/42; native unchanged from verified 8/8. Commit 21c1c954fd50a39231460c97510ef7d6a918d549
Final Ruling: automatic clipboard C4 — next roadmap task rather than M1 claim — cost: copy/paste goal remains pending until C4 tests/builds
Final Ruling: complete history UI — retain explicit latest 100 UI entries; S5 only API paging — cost: old records need future history UI
Final Ruling: before-only same-second gaps — retain compatibility; lossless clients use composite cursor — cost: legacy API consumers must adopt before_id
Final Ruling: multi-worker storage races — keep mandated one worker and in-process upload lock — cost: scaling requires shared coordination
Final Ruling: expired registered files — retain established retention behavior with history metadata — cost: expired metadata scans grow over time
Final Ruling: install and physical/public acceptance — do not claim M1 unit tests establish them — cost: delivery remains gated on later actual acceptance
Final Ruling: reviewer not rerunning tests — use author observed full suites and candidate integration as execution evidence — cost: review is source verification, not second independent test run
Finishing-a-development-branch reviewed: user requests continuing same server project; keep feat/mvp and existing checkout, do not introduce merge/push/PR step.
Windows C++ Build Tools installed successfully in authorized .build path; official Flutter clone retry still fetching.
