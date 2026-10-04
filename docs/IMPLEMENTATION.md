# CrossLink MVP implementation — 2026-10-04

Source authority: CrossLink_跨端文件剪贴板同步软件_开发设计文档.md, supplied by the user.
Location: /home/CrossLink only. All builds, caches and application data live here; operate via SSH.

## Scope and decisions
Implement the document MVP: accounts, rotating refresh sessions, device revocation, websocket presence and heartbeat, reliable per-device delivery/ACK/read, manual clipboard, URL/notification messages, multipart files <=100 MiB, hashes, transfer records and expiration cleanup. Flutter shared Android/Windows client plus browser preview. Defer chunks, OSS, P2P, automatic clipboard and E2EE per the source roadmap.
Single API worker owns websocket connections (document permitted MVP); PostgreSQL persists business state. Docker Compose provides the recommended portable deployment; native systemd deployment accommodates the existing ECS environment. Redis is provisionable with Compose, reserved for multi-worker delivery.
Bind API to 127.0.0.1:8765 and database to 127.0.0.1:55432. No security-group/firewall or existing services changed. Public TLS configuration is prepared for later activation.
Windows binaries require a Windows build host; Linux ECS can validate shared Dart and build web/Android if tools are available. No claim of device-level acceptance until tested on actual Windows/Android devices.

## Execution plan
- [x] Task 1: Create backend test contracts, verify failing API contract, implement FastAPI account/device APIs. Run pytest for registration, login, refresh replay, ownership, logout/revocation.
- [x] Task 2: Add reliable messages, per-recipient receipt persistence, presence, heartbeat, offline replay and ACK/read. Test two-device websocket delivery, repeated ACK, offline broadcast and foreign ACK.
- [x] Task 3: Add streaming uploads, bounded multipart requests, authorized download, SHA256, expiration and transfer history. Test malformed payload, traversal filename, expired file, limit and cross-account access.
- [x] Task 4: Scaffold Flutter Android/Windows/web project, add secure sessions, build-time internal platform configuration, reconnection, manual clipboard, messaging, file progress/cancellation, notifications/tray and Android sharing. Run analyzer and behavior tests, build web and attempt APK.
- [x] Task 5: Deploy project-specific PostgreSQL and API systemd services; test persistent real PostgreSQL/API/websocket/file path through loopback. Add restart test, operational docs, Compose and nginx templates, changelog and Git commits.

## Review focus
Refresh replay and revoked credentials must never restore sessions. Ownership applies to devices, messages, receipts, transfers and files. Broadcast delivery must have independent durable receipts. Uploaded files must stay inside storage and canceled/failed uploads leave no partials. Connections must expire and recover with deduplication; manual clipboard defaults protect user choice.

## Execution ledger
2026-10-04: user explicitly requests implementation using their existing design; preserve that authorization and execute inline. Fresh empty directory provides isolation from existing server projects; initialize a feature branch here. No local generated artifacts.

2026-10-04: 29 backend tests passed. 5 Dart protocol tests passed; analyzer clean before formatting, lint fixes applied after formatter. Real PostgreSQL loopback acceptance passed including API restart and per-device replay; test data cleaned. Web/Android final builds in progress. Native Windows binary and physical-device acceptance remain external to this Linux build host.

2026-10-04 review closure: fixed reconnect while initial pending replay is still in flight, cloned multipart bodies before token-refresh retry, scoped device identity by server/account, refreshed incoming file/clipboard history, preserved Android content URI on system save, and linked transfers to their message for hash verification and read/completion receipts. Added real HTTP/websocket Dart regression coverage: 9 client tests, 29 backend tests. Analyzer and latest Web release build passed. Browser UI acceptance verified login, offline send persistence, realtime reply display and logout; disposable test account was cleaned. APK final build remains in progress; native Windows/physical-device acceptance remains pending.

Android build diagnosis: kernel OOM in uncapped builds; isolated cgroup v1 resident cap 850 MiB with existing swap avoided global OOM, then D8 exposed the 256 MiB JVM metaspace cap. Increased only the project Gradle cap to 512 MiB; rebuilding with cached intermediates through deploy/build-android.py. Added RED/GREEN sanitized-unexpected-error API contract; final backend suite now has 30 tests awaiting the final full run.

Final closure: analyzer clean; latest Web release built; 30 backend tests and 9 Dart tests passed; live PostgreSQL/restart acceptance passed. ARM64 split debug APK successfully built with saved low-memory helper and validated signature, ZIP and ABI. API/database active and enabled, loopback only. Native Windows build and physical-device acceptance remain pending as stated in scope.

2026-10-04 platform follow-up: user authorized automatic implementation and clarified that native login must only show account/password. Added build-time endpoint injection, auto device names, native TLS root, loopback HTTPS gateway/renewal, Android foreground service with native refresh ownership, replay pagination and logout/late-result guards. Windows build kit is prepared for an existing Windows/C++ environment; Linux cannot produce the Windows executable. 30 backend, 13 Dart, 7 native JVM tests, clean analyzer, verified HTTPS/WSS restart acceptance and browser login/peer/message checks have passed. Final 0.2.0 ARM64 APK rebuild, signature, ZIP, engine ABI, public-CA and native service packaging verification passed. Windows build kit is packaged from committed source.
