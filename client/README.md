# CrossLink Flutter client

Shared Android/Windows source plus browser preview. Configure the server on the login screen.
Builds and caches on this ECS stay in `/home/CrossLink`; source `/home/CrossLink/deploy/flutter-env.sh` before invoking Flutter.
See the project README for tunnels, native platform requirements, build commands and known limitations.
Run `flutter analyze` and `flutter test`. The Windows binary requires a Windows build host; Android debug APK is for development testing.
