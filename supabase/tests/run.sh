#!/usr/bin/env bash
# Replays every migration from an empty database and runs the security
# assertions against the result.
#
#   supabase/tests/run.sh
#
# Requires Docker. Nothing here touches the real Supabase project.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

CONTAINER="htbiz-migration-test"
PGPASSWORD_VALUE="postgres"
IMAGE="postgres:17-alpine"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

echo "==> Starting $IMAGE"
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD="$PGPASSWORD_VALUE" \
  -e POSTGRES_DB=htbiz \
  "$IMAGE" >/dev/null

echo -n "==> Waiting for Postgres"
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready -U postgres -d htbiz >/dev/null 2>&1; then
    echo " ready"
    break
  fi
  echo -n "."
  sleep 1
done

run_sql() {
  local label="$1" file="$2" extra="${3:-}"
  echo "==> $label"
  # ON_ERROR_STOP makes psql exit non-zero on the first failed statement, so a
  # broken migration fails the run instead of scrolling past.
  docker exec -i "$CONTAINER" \
    psql -v ON_ERROR_STOP=1 -U postgres -d htbiz $extra < "$file"
}

run_sql "Stubbing the Supabase platform"   "$HERE/00_stub_platform.sql"
run_sql "Baseline schema"                  "$HERE/01_baseline.sql"
run_sql "supabase_full_migration.sql"      "$ROOT/supabase_full_migration.sql"
run_sql "20260416_push_notifications.sql"  "$ROOT/supabase/migrations/20260416_push_notifications.sql"
run_sql "20260902000000_production_hardening.sql" \
        "$ROOT/supabase/migrations/20260902000000_production_hardening.sql"

# Re-apply the hardening migration: it must be safe to run twice.
run_sql "Re-running hardening (idempotency check)" \
        "$ROOT/supabase/migrations/20260902000000_production_hardening.sql"

run_sql "Security assertions" "$HERE/02_security_assertions.sql"

echo
echo "==> All migrations applied and all assertions passed."
