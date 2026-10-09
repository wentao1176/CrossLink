# CrossLink native acceptance

Source and automated checks (2026-10-09): Windows current-user startup command quoting/bounds and native clipboard helpers pass real compiler/OS checks; shared client pause retains login, prevents reconnect and resumes; Android JVM11 checks pass. These do not certify all native GUI behavior.

Pending physical checks: Windows setup/upgrade/uninstall, single instance activation, close to tray, start after login, notification click, direct paste into another app, cancelled/overwritten file saves. Android physical model/version, permission denied, share before/after launch, background persistence, durable pause after process recreation, resume, focus clipboard, actual target-app paste and SAF file open.

Clipboard text/URL is first release scope. Android ordinary background reading is unavailable from Android10; open CrossLink to observe a copy made in another app. Background writes are deferred until focus to preserve unknown local changes. App force stop is not promised to retain reception.

Public relay access stays closed pending explicit user authorization. QA uses verified TLS through SSH and USB reverse, with its endpoint built in.
