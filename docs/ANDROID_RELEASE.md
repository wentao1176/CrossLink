# Android release 0.3.0

Fixed namespace com.crosslink.crosslink. Production application ID com.crosslink.crosslink; QA ID com.crosslink.crosslink.qa and visible QA label. ARM64 only. VersionCode starts with pubspec build3 (split ABI adds its offset); next upgrade uses build4 or greater with the same key.

`deploy/build-android.py --channel qa|production --mode release` uses the locked server Flutter SDK, one worker and existing 850MiB resident/2800MiB memory+swap cap. Build configurations inject hidden HTTPS endpoints. Public CA remains embedded; hostname/IP checks remain enabled.

Release signing under .tools/signing (0700 directory/0600 files): JKS crosslink-release.jks plus protected key.properties. Alias crosslink, RSA3072 SHA256withRSA, 10000-day validity. Credentials are neither printed nor exported into the Git source archive, Windows kit or public artifacts. The first key must be retained; a private local backup is under data/backups/signing. This is a local recovery copy, not an off-server backup.

Missing release configuration was observed to accept debug signing in the old build. The updated task graph rejects assembling release without valid release credentials; debug fallback is forbidden. App-label resources explicitly enable resValues for current AGP. Debug test tasks can still run without release secrets.

Final artifacts must be checked with apksigner/aapt for package, versionCode, debuggable flag, ARM64 native libraries and the public CA, with source/configuration/SHA256 manifests. Actual device installation and same-key upgrade acceptance remain required. Existing 0.2 debug signature differs from this release identity; QA can install alongside it. Production debug-to-release migration requires preserving downloaded user files before uninstalling the debug app.

Verified final0.3.0: source5009205be86b566283fdd9ce659c5412f4ab5ff4; ARM64 split versionCode2003, min24/target36, release/nondebuggable. Both channel signatures verify against certificate SHA256ef5cd9fac903e4c3737d584b6bdf5858d374397e47b7e67771288381ba5af56c. Per-channel manifests include package/signature checks; root manifest/SHA256SUMS cover the final artifacts. Release lint No issues found; explicit loopback domain matching retained base cleartext rejection, see [Android configuration reference](https://developer.android.com/privacy-and-security/security-config). Actual phone installation/upgrade remains pending.
