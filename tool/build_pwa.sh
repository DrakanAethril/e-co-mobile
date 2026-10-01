#!/usr/bin/env bash
# Builds e-CO as a PWA and publishes it into moncampus, which serves it at /eco-app/ - the same
# origin as the API, so the app needs no API_BASE_URL (lib/config.dart) and no CORS. Never pass
# --dart-define=API_BASE_URL here: the service worker sends the offline queue to its own origin
# (web/eco_sw.js), and the two must agree.
#
#   tool/build_pwa.sh [<moncampus repo>]
#
# CanvasKit is served from moncampus rather than Google's CDN: the app must reopen offline, and a
# CDN the service worker does not cache would leave it blank. Only the files the CanvasKit
# renderer loads are kept - not the skwasm renderer, not the debug symbols, not Flutter's own
# service worker (replaced by eco_sw.js, see there why).
set -euo pipefail

ECO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONCAMPUS_REPO="${1:-/Users/Shared/Projets/Symfony/moncampus}"
TARGET="$MONCAMPUS_REPO/public/eco-app"
FLUTTER=$(command -v flutter || echo /Users/Shared/flutter/bin/flutter)

if [ ! -d "$MONCAMPUS_REPO/public" ]; then
    echo "No public/ under $MONCAMPUS_REPO" >&2
    exit 1
fi

cd "$ECO_DIR"
"$FLUTTER" pub get
"$FLUTTER" build web --release --web-renderer canvaskit --no-web-resources-cdn --base-href /eco-app/ --no-source-maps

OUT="$ECO_DIR/build/web"
rm -f "$OUT/flutter_service_worker.js" "$OUT/.last_build_id"
rm -f "$OUT"/canvaskit/skwasm.*
find "$OUT/canvaskit" -name '*.symbols' -delete

mkdir -p "$TARGET"
rsync -a --delete --exclude README.md "$OUT/" "$TARGET/"

echo "PWA $(grep -m1 '^version:' pubspec.yaml | awk '{print $2}') published to $TARGET ($(du -sh "$TARGET" | cut -f1))."
