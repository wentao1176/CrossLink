#!/usr/bin/env bash
set -euo pipefail
source /home/CrossLink/deploy/flutter-env.sh
cd /home/CrossLink/client
flutter analyze
flutter test
flutter build web --release --no-wasm-dry-run
flutter build apk --debug --target-platform android-arm64
cp build/app/outputs/flutter-apk/app-debug.apk /home/CrossLink/artifacts/CrossLink-0.1.0-arm64-debug.apk
