#!/usr/bin/env bash
# Run an app with Supabase config injected from .env.
# Usage:  tool/run.sh teacher   |   tool/run.sh student   |   tool/run.sh probe
# Extra flutter args pass through:  tool/run.sh student -d <deviceId>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a; source "$ROOT/.env"; set +a

case "${1:-}" in
  teacher) DIR="$ROOT/apps/teacher" ;;
  student) DIR="$ROOT/apps/student" ;;
  probe)   DIR="$ROOT/tools/ble_probe" ;;
  *) echo "usage: tool/run.sh {teacher|student|probe} [flutter args]"; exit 1 ;;
esac
shift

cd "$DIR"
exec flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
  "$@"
