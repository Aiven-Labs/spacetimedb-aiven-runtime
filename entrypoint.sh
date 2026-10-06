#!/bin/sh
# Start SpacetimeDB, publish the module, run any post-publish calls, then stay in the
# foreground with the server.
#
# Environment:
#   PORT                  port to listen on (default 3000; must match the port set on the Aiven service)
#   DB_NAME               database name clients connect to (default "app")
#   PUBLISH_DELETE_DATA   set to 1 to wipe the database on every start (schema-breaking changes)
#   POST_PUBLISH_CALLS    reducers to call once published, one per line:  reducer_name arg1 arg2
#                         Use the snake_case reducer name (setGreeting is called as set_greeting).
#                         Args are split on whitespace, so keep each one a single word (URLs and
#                         tokens are fine). Runs as the owner identity, which is what you need to
#                         hand the module its own configuration or secrets.
set -eu

PORT="${PORT:-3000}"
DB_NAME="${DB_NAME:-app}"
SERVER="http://127.0.0.1:${PORT}"

mkdir -p /data/db "$HOME"

spacetime start --data-dir /data/db --listen-addr "0.0.0.0:${PORT}" &
SERVER_PID=$!
trap 'kill -TERM "$SERVER_PID" 2>/dev/null || true' TERM INT

i=0
until spacetime server ping "$SERVER" >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then echo "SpacetimeDB did not come up" >&2; exit 1; fi
  sleep 1
done

# Publishing is idempotent: the first start creates the database, later starts update
# the module in place and keep the data (the CLI identity under $HOME owns it).
if [ -f /opt/app/module.wasm ]; then ARTIFACT="--bin-path /opt/app/module.wasm"; else ARTIFACT="--js-path /opt/app/bundle.js"; fi
EXTRA=""
[ "${PUBLISH_DELETE_DATA:-0}" = "1" ] && EXTRA="--delete-data"

# shellcheck disable=SC2086
if ! spacetime publish "$DB_NAME" --server "$SERVER" $ARTIFACT $EXTRA -y; then
  echo "publish failed" >&2; kill "$SERVER_PID" 2>/dev/null || true; exit 1
fi

if [ -n "${POST_PUBLISH_CALLS:-}" ]; then
  printf '%s\n' "$POST_PUBLISH_CALLS" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    # shellcheck disable=SC2086
    set -- $line
    if OUT=$(spacetime call "$DB_NAME" --server "$SERVER" -- "$@" 2>&1); then
      echo "post-publish: called $1"
    else
      echo "post-publish: $1 failed:" >&2; echo "$OUT" | tail -5 >&2
      kill "$SERVER_PID" 2>/dev/null || true; exit 1
    fi
  done
fi

echo "ready: database '$DB_NAME' on port $PORT"
wait "$SERVER_PID"
