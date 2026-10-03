# Verification record — 2026-10-04

All execution took place via SSH on the aliyun ECS in `/home/CrossLink`.

| Check | Result | Evidence |
| --- | --- | --- |
| Backend contracts | 30 tests passed | `server/tests/test_api.py`; account/session/device ownership, replay/ACK/read, multipart/files/retention |
| Dart behavior | 9 tests passed | Protocol plus real HTTP token-refresh multipart retry, websocket reconnect during slow pending replay, file download/complete SAF URI |
| Static analysis | Passed, no issues | `flutter analyze` after review fixes |
| Web release | Built | `client/build/web`, copy in `artifacts/web` |
| Real PostgreSQL/API | Passed | `deploy/smoke_live.py`; presence, <2s push, file SHA256/ownership, API restart persistence, revocation |
| Browser UI | Passed | Login, offline send stored for target, live reply displayed in message history, logout; disposable records removed |
| Android APK | Built and verified | ARM64-only split debug APK, v2 signature, ZIP integrity and matching Flutter engine; `logs/android-build.log`, `logs/apk-verification.log`, `artifacts/SHA256SUMS` |
| Windows executable | Not built | Linux host; requires Windows Flutter/Visual Studio toolchain |
| Native device acceptance | Pending | No physical Android/Windows session; OS notifications, actual sharing/save/open and tray require device testing |

## Source review
A separate read-only reviewer found six defects and confirmed their closure in the final source diff: reconnect starvation, replaying finalized multipart, stale incoming transfer history, missing original message/hash metadata, incomplete Android content URI, and cross-account device UUID reuse. Added behavior regressions cover the network and save boundary fixes. Native save is mocked only at the platform channel boundary; this is not a physical-device test.

## Deployment
Dedicated systemd API/database services are enabled. API binds `127.0.0.1:8765`; PostgreSQL binds `127.0.0.1:55432`. No security group, firewall, domain or public TLS configuration was enabled. Single websocket worker. Existing unrelated applications remain in place.

`deploy/migrations/001_transfer_message_id.sql` was applied to the existing PostgreSQL schema; it adds a nullable foreign key and backfills matching historical file messages. No project data was reset.

## Remaining acceptance limits
This is a development MVP. Android foreground service/OS background survival, production signing, Windows binary, domain/TLS, and physical-device acceptance remain future work. Browser credentials stay in memory. The local publisher is single-worker; Redis/multi-worker, chunks/resume, OSS, automatic clipboard, P2P and E2EE are deferred per the roadmap. Native PostgreSQL is the distribution-provided 13.23; the unexecuted Compose alternative targets 16.

## Final artifact
`artifacts/CrossLink-0.1.0-arm64-debug.apk`: 95,592,745 bytes, version 0.1.0 (split version code 2001), minSdk 24, targetSdk 36, only `arm64-v8a` libraries.
SHA256: `290bac816794f79affd36e24fdfb21a0ab06e09fd1999e0b2ec29628f1e4bfe6`.

Final full runs: 30 backend tests passed (one third-party Starlette/AnyIO deprecation warning), 9 Dart tests passed, real PostgreSQL/websocket/file/restart/revocation checks passed and cleaned their disposable rows. Services remain active and enabled, with loopback listeners only. Native device acceptance is still pending.

Build resource evidence: uncapped Gradle triggered kernel OOM; an 850 MiB build cgroup with existing swap avoided global OOM. D8 then hit the 256 MiB metaspace cap, raised to 512 MiB. The saved helper subsequently built successfully. Final packaging uses `--split-per-abi --target-platform android-arm64`, excluding incompatible plugin-only architectures. Source/behavior tests were not rerun after this packaging-only flag change; APK signing, ZIP and ABI checks were rerun on the final binary.
