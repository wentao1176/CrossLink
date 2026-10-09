# Android release 0.3.0

Fixed namespace com.crosslink.crosslink. Production application ID com.crosslink.crosslink; QA ID com.crosslink.crosslink.qa and visible QA label. ARM64 only. VersionCode starts with pubspec build3 (split ABI adds its offset); next upgrade uses build4 or greater with the same key.

`deploy/build-android.py --channel qa|production --mode release` uses the locked server Flutter SDK, one worker and existing 850MiB resident/2800MiB memory+swap cap. Build configurations inject hidden HTTPS endpoints. Public CA remains embedded; hostname/IP checks remain enabled.

Release signing under .tools/signing (0700 directory/0600 files): JKS crosslink-release.jks plus protected key.properties. Alias crosslink, RSA3072 SHA256withRSA, 10000-day validity. Credentials are neither printed nor exported into the Git source archive, Windows kit or public artifacts. The first key must be retained; a private local backup is under data/backups/signing. This is a local recovery copy, not an off-server backup.

Missing release configuration was observed to accept debug signing in the old build. The updated task graph rejects assembling release without valid release credentials; debug fallback is forbidden. App-label resources explicitly enable resValues for current AGP. Debug test tasks can still run without release secrets.

Final artifacts must be checked with apksigner/aapt for package, versionCode, debuggable flag, ARM64 native libraries and the public CA, with source/configuration/SHA256 manifests. Actual device installation and same-key upgrade acceptance remain required. Existing 0.2 debug signature differs from this release identity; QA can install alongside it. Production debug-to-release migration requires preserving downloaded user files before uninstalling the debug app.
