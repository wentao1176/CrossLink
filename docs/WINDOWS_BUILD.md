# Windows build 0.3.0

Authoritative source and export originate from /home/CrossLink via SSH. Export a committed tree with `deploy/export-build-source.py`; its archive contains Git-tracked sources, public CA, public build configurations and source.json. It excludes signing secrets, server environment, TLS private material and development caches.

Authorized local workspace: D:/aliyun/CrossLink/.build. Flutter5fc346839b5d0eef006ed8404392afb4dfae428d, Microsoft C++ Build Tools17.14 and Windows SDK10.0.26100 are installed there. Inno Setup6.7.3 portable compiler was fetched from the official GitHub asset API, official SHA256 matched and Pyrsys Authenticode was valid; user explicitly approved its installation after automatic policy initially rejected the action.

Run the exported `deploy/build-windows.ps1 -BuildRoot D:/aliyun/CrossLink/.build -FlutterRoot D:/aliyun/CrossLink/.build/toolchain/flutter -Channel qa -PackageInstaller -IsccPath D:/aliyun/CrossLink/.build/toolchain/InnoSetup/ISCC.exe`. The script validates source metadata, pinned SDK and locked dependencies, tests on Windows, builds release ZIP/setup and records source/configuration/artifact hashes. Repeat for production; both source hashes must match.

QA and production have separate installation names and resource product names. QA uses a separate secure session key. Startup is opt-in under HKCU; uninstall runs this executable's --remove-startup before removing it. Upgrade does not delete user preferences or received files. Installer privileges are current-user only. No Authenticode publisher certificate for the CrossLink application has been obtained; artifact hashes do not assert publisher signing.

Native GUI/install/upgrade/uninstall acceptance remains separate from compilation and hashes. Private QA uses SSH forwarding; production public ports remain closed.

Windows builds must use lib/main_windows.dart, selected by the helper. Desktop-only FFI is isolated from Android's AOT graph; SDK/dependency versions remain pinned. On Windows without symlink privilege, package restore finishes then the helper creates directory junctions under BuildRoot to caches under that same root. Existing links are verified and unlinked without recursion before restore. It does not turn on Developer Mode or elevate builds. C++ ATL is also required by the secure-storage plugin.

Package official x64 CRT DLLs app-local from the installed MSVC redistribution directory before ZIP/setup. Required dependencies (MSVCP140/VCRUNTIME140/VCRUNTIME140_1) are verified from dumpbin; no global runtime installer or administrator prompt is needed by the CrossLink setup. Preserve redistribution notices and the full release directory.
