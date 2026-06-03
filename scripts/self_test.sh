#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BINARY="$ROOT_DIR/build/ActiveLeft.app/Contents/MacOS/ActiveLeft"
SELF_TEST_LOG="$(mktemp "${TMPDIR:-/tmp}/activeleft-self-test.XXXXXX.log")"

cleanup() {
  rm -f "$SELF_TEST_LOG"
}
trap cleanup EXIT

if [[ ! -x "$APP_BINARY" ]]; then
  "$ROOT_DIR/scripts/build_app.sh" release
fi

BEFORE_PMSET="$(pmset -g custom)"
"$APP_BINARY" --self-test >"$SELF_TEST_LOG" 2>&1 &
SELF_TEST_PID=$!

sleep 1
ACTIVE_ASSERTIONS="$(pmset -g assertions)"

wait "$SELF_TEST_PID"
AFTER_PMSET="$(pmset -g custom)"

if [[ "$BEFORE_PMSET" != "$AFTER_PMSET" ]]; then
  echo "pmset changed during self-test" >&2
  exit 1
fi

if ! grep -q "PreventUserIdleDisplaySleep" <<<"$ACTIVE_ASSERTIONS"; then
  echo "display sleep assertion was not observed during self-test" >&2
  exit 1
fi

if ! grep -q "caffeinate" <<<"$ACTIVE_ASSERTIONS"; then
  echo "caffeinate was not observed during self-test" >&2
  exit 1
fi

cat "$SELF_TEST_LOG"
echo "ActiveLeft self-test passed"
