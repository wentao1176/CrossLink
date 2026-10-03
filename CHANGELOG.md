# Changelog

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
