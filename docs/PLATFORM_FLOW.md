# Unified platform flow — 2026-10-04

Windows and Android show only account/password for login. Platform endpoint comes from build configuration, device names are automatic, connection and same-account peer discovery are automatic after login, and sending defaults to all other devices. No endpoint entry or display exists in login/settings/errors. Registration can still request an email.

Native builds use `.tools/client-build.json` on ECS; Windows build kits carry `config/client-build.json`. Source consumes `CROSSLINK_API_URL` at build time. Web uses its current origin. Previously editable endpoints are discarded; saved sessions remain scoped to their deployment origin.

Native TLS trusts the bundled CrossLink platform root certificate. Only the public certificate ships. Private signing/server keys are excluded from Git and packages. Hostname/IP validation stays enabled. A separate project gateway proxies the existing single API worker, initially binds loopback at 8443 and is verified against the app root. Security groups are unchanged. Public activation remains a separate operation.

Android background reception uses a remoteMessaging foreground service. Native refresh ownership prevents UI/background refresh races. Credentials are encrypted with Android Keystore, messages persist before ACK, and explicit logout stops the service and clears credentials. Physical-device acceptance remains required.

Windows builds use `deploy/build-windows.ps1` to checkout and verify the official Flutter Git tag and pinned commit, analyze/test/build and ZIP the full runtime. Windows with Visual Studio C++ tools is required. No Windows executable is claimed from this Linux ECS. Automatic privileged toolchain installation script creation was rejected by automatic review with only "blocked by policy" provided; the final script does not elevate privileges or install C++ tools.
