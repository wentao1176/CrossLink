#!/usr/bin/env bash
set -euo pipefail
source /home/CrossLink/deploy/flutter-env.sh
cd /home/CrossLink/client
flutter analyze
flutter test
flutter build web --release --no-wasm-dry-run
mkdir -p /home/CrossLink/artifacts/web
cp -a build/web/. /home/CrossLink/artifacts/web/
python3 /home/CrossLink/deploy/build-android.py
cp build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk /home/CrossLink/artifacts/CrossLink-0.1.0-arm64-debug.apk
