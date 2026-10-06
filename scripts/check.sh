#!/bin/sh
# Post-deploy check: is the server up, and is the database published?
#   scripts/check.sh https://<service>.aiven.app my-db
set -eu
BASE="${1:?usage: check.sh <base-url> [db-name]}"; DB="${2:-app}"
printf 'ping            '; curl -fsS -m 20 -o /dev/null -w '%{http_code}\n' "$BASE/v1/ping"
printf 'database        '; curl -fsS -m 20 -o /dev/null -w '%{http_code}\n' "$BASE/v1/database/$DB"
