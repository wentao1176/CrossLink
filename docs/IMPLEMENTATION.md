# CrossLink MVP implementation — 2026-10-04

Source authority: CrossLink_跨端文件剪贴板同步软件_开发设计文档.md, supplied by the user.
Location: /home/CrossLink only. All builds, caches and application data live here; operate via SSH.

## Scope and decisions
Implement the document MVP: accounts, rotating refresh sessions, device revocation, websocket presence and heartbeat, reliable per-device delivery/ACK/read, manual clipboard, URL/notification messages, multipart files <=100 MiB, hashes, transfer records and expiration cleanup. Flutter shared Android/Windows client plus browser preview. Defer chunks, OSS, P2P, automatic clipboard and E2EE per the source roadmap.
Single API worker owns websocket connections (document permitted MVP); PostgreSQL persists business state. Docker Compose provides the recommended portable deployment; native systemd deployment accommodates the existing ECS environment. Redis is provisionable with Compose, reserved for multi-worker delivery.
Bind API to 127.0.0.1:8765 and database to 127.0.0.1:55432. No security-group/firewall or existing services changed. Public TLS configuration is prepared for later activation.
Windows binaries require a Windows build host; Linux ECS can validate shared Dart and build web/Android if tools are available. No claim of device-level acceptance until tested on actual Windows/Android devices.

## Execution plan
- [ ] Task 1: Create backend test contracts, verify failing API contract, implement FastAPI account/device APIs. Run pytest for registration, login, refresh replay, ownership, logout/revocation.
- [ ] Task 2: Add reliable messages, per-recipient receipt persistence, presence, heartbeat, offline replay and ACK/read. Test two-device websocket delivery, repeated ACK, offline broadcast and foreign ACK.
- [ ] Task 3: Add streaming uploads, bounded multipart requests, authorized download, SHA256, expiration and transfer history. Test malformed payload, traversal filename, expired file, limit and cross-account access.
- [ ] Task 4: Scaffold Flutter Android/Windows/web project, add secure sessions, explicit endpoint configuration, reconnection, manual clipboard, messaging, file progress/cancellation, notifications/tray and Android sharing. Run analyzer and behavior tests, build web and attempt APK.
- [ ] Task 5: Deploy project-specific PostgreSQL and API systemd services; test persistent real PostgreSQL/API/websocket/file path through loopback. Add restart test, operational docs, Compose and nginx templates, changelog and Git commits.

## Review focus
Refresh replay and revoked credentials must never restore sessions. Ownership applies to devices, messages, receipts, transfers and files. Broadcast delivery must have independent durable receipts. Uploaded files must stay inside storage and canceled/failed uploads leave no partials. Connections must expire and recover with deduplication; manual clipboard defaults protect user choice.

## Execution ledger
2026-10-04: user explicitly requests implementation using their existing design; preserve that authorization and execute inline. Fresh empty directory provides isolation from existing server projects; initialize a feature branch here. No local generated artifacts.
