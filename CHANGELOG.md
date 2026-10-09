# Changelog

## 0.2.0 — 2026-10-04
- Windows/Android login now requests only account/password; platform comes from build configuration and device names are automatic. Same-account devices connect automatically; sending defaults to peers.
- Add Android remoteMessaging foreground service with Keystore-encrypted credentials, a single refresh/socket owner, durable delivery before ACK, paginated offline replay, heartbeat and prompt reconnect on expiry.
- Quiesce in-flight native token rotation on logout; discard late Flutter refresh results and stale background owner events.
- Bundle only the public platform CA; retain certificate hostname/IP verification. Deploy loopback TLS gateway and private automatic leaf-certificate renewal, keeping public activation deferred.
- Add remote Android/JVM build helpers and a pinned official Flutter Windows build kit. Windows exe and native-device acceptance still require their respective host/device.
- Exclude private TLS files from both Git and Docker contexts.
- Final validation: 30 backend, 13 Dart, 7 native JVM tests, clean analyzer, Web release, verified HTTPS/WSS restart acceptance, browser login/peer/message checks and ARM64 APK signature/ZIP/assets verification.

## 0.1.0 — 2026-10-04
- Phase 1: FastAPI, PostgreSQL, registration/login, Argon2 passwords, JWT, rotating refresh/logout and ownership-aware devices.
- Phase 2: Authenticated websocket, device presence, heartbeat, session expiry and revocation.
- Phase 3: Account-bound text/URL/notification messages with independent durable recipient receipts and idempotent send keys.
- Phase 4: Manual clipboard, SHA256/origin metadata, history and one-click copy.
- Phase 5: 100 MiB multipart files, SHA256, authorized attachment download, per-device transfer records and 7-day cleanup.
- Phase 6: Flutter Windows source with tray, close-to-tray and local notifications; Windows build/device validation still required.
- Phase 7: Flutter Android share intents, notifications and user-chosen file save; app closed/background delivery relies on later pending replay (no foreground service).
- Phase 8: Offline receipt replay, idempotent ACK/read, bounded reconnection and client history cache.
- Added browser preview, native systemd deployment, Compose/nginx templates and restart acceptance script.
- Deferred Phases 9–10 and V2 features: chunk/resume/dedup storage, automatic clipboard, OSS, Redis fanout, P2P and E2EE.

### Review fixes
- Recover when a websocket disconnects during pending-message replay; resend multipart uploads after token refresh.
- Keep device UUIDs scoped to server/account and refresh histories on incoming file/clipboard events.
- Preserve Android Storage Access Framework content URIs and validate file hashes in every download path.
- Associate transfer history with original messages so downloads can report read/completion correctly.
- Add additive PostgreSQL migration `deploy/migrations/001_transfer_message_id.sql`; applied to this server.
- Unexpected API errors now return sanitized JSON with a request ID; test temp/cache paths stay inside the project.
- Added a memory-constrained Android build helper for the 2 GB ECS and adjusted Gradle metaspace after D8 hit its previous cap.
- Built and verified an ARM64-only split debug APK; final native-library filters match the included Flutter engine.
- Final validation: 30 backend tests, 9 Dart tests, analyzer, Web release, real PostgreSQL/restart acceptance and APK integrity/signature.

## Unreleased — 2026-10-09
- Android UI reattach uses native connection snapshots and ordered state events; old owners and older state revisions are ignored.
- Device names survive sign-in and revocation; current-device display follows remote rename, and stale reloads cannot repopulate a logged-out session.
- Delivery/read receipts reach senders in real time over both transports; reconnect history reconciles missed updates and stale events cannot restore logged-out history.
