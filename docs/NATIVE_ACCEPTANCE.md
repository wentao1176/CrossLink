# CrossLink native acceptance 0.3.0

Current evidence and pending matrix: [0.3.0 acceptance](acceptance/0.3.0.md). Artifacts were built from5009205be86b566283fdd9ce659c5412f4ab5ff4.

Windows11 Home10.0.26200: current-user QA setup/start/single-instance/reinstall/uninstall passed. App-local signed CRT DLLs and Flutter engine were actually loaded. Default startup stayed disabled. Reinstall is not a version upgrade test. Native clipboard helpers and startup command quoting/bounds have compiler/OS checks; these do not certify cross-app paste, tray interactions, notifications or post-reboot behavior.

Shared client57 tests/analyzer and native Android JVM11 tests pass. Android QA/production release APKs have matching retained release signer, correct namespace/versionCode2003/min24/target36, ARM64 only, nondebuggable, CRC/public-CA/private-key checks. No physical phone participated; user explicitly deferred USB testing to finish packages.

Remaining A1 matrix: actual Windows/Android same-account login, two-way system paste, large file SAF save/open/overwrite/cancel, native tray/notification click, startup after restart, Android background/lock/power/notification permission, sharing, network changes, actual version upgrade and three-device broadcast. Simulated HTTPS/WSS and JVM results are supplemental evidence.

Clipboard supports text/URL. [Android10 clipboard access requires app focus or default IME](https://developer.android.com/about/versions/10/privacy/changes#clipboard-data). This ordinary app reads a new other-app copy when CrossLink gains focus, and defers remote writes until focus to preserve unseen local changes. Force-stop continuity is not promised.

Public access remains closed pending explicit user authorization. QA uses verified TLS through developer SSH and later USB reverse; no server-address UI exists. One test notification shortcut remains after uninstall because automatic review rejected cleanup with onlyblocked by policy.
