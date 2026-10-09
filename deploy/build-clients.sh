#!/usr/bin/env bash
set -euo pipefail
channel=${1:-production}
case "$channel" in qa|production) ;; *) echo "Invalid build channel"; exit 2;; esac
source /home/CrossLink/deploy/flutter-env.sh
cd /home/CrossLink/client
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub
flutter --no-version-check build web --release --no-pub --no-wasm-dry-run
mkdir -p /home/CrossLink/artifacts/0.3.0/web
cp -a build/web/. /home/CrossLink/artifacts/0.3.0/web/
/home/CrossLink/.venv/bin/python /home/CrossLink/deploy/build-android.py --channel "$channel" --mode release
