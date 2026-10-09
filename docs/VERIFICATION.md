# Current verification: CrossLink0.3.0, 2026-10-09

Current source/build/installer/signature/platform/backup evidence and explicit remaining gates are in [0.3.0 acceptance](acceptance/0.3.0.md). Current results: backend55, shared Dart57, native JVM11; Windows QA/production setup+ZIP and signed ARM64 release APKs built from the same5009205be86b566283fdd9ce659c5412f4ab5ff4. Physical phone, public activation, native version upgrade and72h usage remain pending. Known Minor notification-permission label issue is recorded there.

The following sections are historical evidence for0.1/0.2 and stabilization, not the current release status.

# Verification record — 2026-10-04

All development, builds, caches and execution took place via SSH on aliyun in `/home/CrossLink`. No local source/build artifact was created or downloaded.

| Check | Result | Evidence |
| --- | --- | --- |
| Backend contracts | 30 passed | `logs/backend-final.log`; ownership, rotating refresh/revocation, receipts, files/retention |
| Dart behavior | 13 passed | `logs/client-tests-final.log`; account/password-only login, native refresh delegation, late refresh/start rejection, reconnect/presence, multipart retry and full SAF URI |
| Android transport JVM tests | 7 passed | `logs/native-tests-final.log`; real MockWebServer HTTP/websockets, durable ACK, one rotation, close-before-auth recovery, 501-message drain, revocation, logout/write quiescence and slow-ACK heartbeat |
| Static analysis | Clean | `logs/client-analysis-final.log` |
| Web release | Built | `client/build/web`, `artifacts/web`, `logs/web-build.log` |
| HTTPS/WSS real platform | Passed | `logs/tls-live.log`; bundled CA verified, real PostgreSQL, two-device presence, <2s clipboard delivery, multipart/SHA256/ownership, restart persistence, revocation |
| Browser UI | Passed | Only username/password, automatic live connection and same-account online PC discovery, incoming message displayed/ACKed, no endpoint in settings, logout. Disposable account/rows/credentials removed. |
| Android 0.2.0 APK | Built and verified | Final rebuild 98.2 seconds; v2 signature, ZIP integrity, ARM64-only Flutter engine, bundled public CA and native service/permission verified |
| Windows build kit | Prepared | Official Flutter 3.47.6 Git tag resolves to pinned commit; PowerShell parser passed. Package only committed source, public CA and internal endpoint config. No Windows exe built on Linux. |
| Native-device acceptance | Pending | Actual Windows tray/notifications and Android FGS/permissions/SAF behavior need the relevant host/device. JVM/channel-boundary tests are not physical-device tests. |

## Review closure

An independent read-only reviewer confirmed closure of login, TLS, packaging and native session lifecycle findings. Private TLS files are excluded from Docker contexts and Git. Native replay now drains full pages, handles close-before-auth promptly, saves messages before ACK, keeps one refresh owner, and quiesces pending refresh saves before explicit logout clears credentials. Durable store writes check the owning session atomically; Flutter rejects stale refresh/start results and obsolete native owner events. A final slow-ACK RED/GREEN regression moved network receipts/replay off the heartbeat scheduler.

The browser found initially stale own-device presence after authentication; device list refresh now runs after authenticated connection and is covered by the existing network regression. Settings reflect version 0.2.0 and native background reception.

## Deployment and limits

Dedicated API/database/TLS gateway services and certificate-renewal timer are enabled. API: `127.0.0.1:8765`; PostgreSQL: `127.0.0.1:55432`; TLS gateway: `127.0.0.1:8443`. No security-group/firewall/public listener changes. Public listener example is saved but not activated. Native external connection therefore remains unavailable until later public activation.

The Android package uses a development signature and ARM64-only split packaging, minSdk 24, targetSdk 36. Production signing and actual OS/phone acceptance remain pending. Windows requires a Windows/C++ build host. Privileged automatic C++ installation script creation was rejected by automatic review with only "blocked by policy" given; the replacement script uses an existing C++ toolchain and does not elevate.

Root/server TLS private keys stay on the ECS. Only the public root is bundled, and IP/hostname validation remains enabled. Leaf certificate renewal is automatic; its actual systemd oneshot finished successfully with a valid-certificate no-op. The JVM tests use HTTP locally; the real deployment acceptance uses verified HTTPS/WSS.

This remains the design document MVP: single websocket worker, native PostgreSQL 13.23, manual clipboard, 100 MiB files, seven-day retention. Redis fanout, resume/chunks, OSS, automatic clipboard, P2P, E2EE, email verification and password recovery are deferred. The alternative Docker/PostgreSQL 16 Compose template is not running.

## Build resource evidence

APK/JVM builds are isolated under an 850 MiB resident/2800 MiB memory-plus-swap cgroup, use existing swap, one Gradle worker and a 512 MiB JVM heap/metaspace. Existing unrelated services are not modified. The first 0.2.0 APK build took 553 seconds; the final incremental rebuild took 98.2 seconds.

## Final artifacts

CrossLink-0.2.0-arm64-debug.apk: 121719745 bytes; version 0.2.0, split version code 2002, minSdk 24, targetSdk 36, only arm64-v8a.
SHA256: 17a6c943f37411b827fcf399e4ac78d4c95a9bcfbc43bb815c0c00beaa600718.

Windows source build kit is packaged from the recorded Git revision, contains public CA and internal HTTPS configuration, and is checked for ZIP integrity and absence of private keys. Checksums for both packages are in artifacts/SHA256SUMS. No Windows executable or physical-device acceptance is claimed.

## 2026-10-09 stabilization follow-up

Five audited source defects were fixed with observed regression failures and passing results. Backend full suite: 42 passed (one existing third-party deprecation); shared client: 26 passed, analyzer clean; native transport: 8 passed with fresh JVM result. Real PostgreSQL candidate uses an isolated temporary schema and loopback HTTPS/WSS with the bundled CA; sender delivery/read, persisted renamed device, same-second cursor, file/hash/ownership and revocation checks passed. Production source has not yet been reloaded at this stage.

One independent source review identified early receipt-before-HTTP ordering, outgoing-copy false read, and old device reload overwrite. Four controlled regressions (including legacy cached false read) were seen failing, then fixed; the entire Dart suite passed. Receipts are buffered within the current session until their message appears, copying a sent record does not alter server status, device results are ordered, and legacy unverified outgoing read is revalidated from server history. Automatic copy/paste C4 and native package/device acceptance remain the next stage.
