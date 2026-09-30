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

CONTAINER="htbiz-migration-test-$$"
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
ready=0
for _ in $(seq 1 60); do
  # The image starts a temporary socket-only server during initialization.
  # pg_isready can accept that server before POSTGRES_DB exists. Require a
  # successful query over TCP to the final server and the intended database.
  if docker exec -e PGPASSWORD="$PGPASSWORD_VALUE" "$CONTAINER" \
      psql -h 127.0.0.1 -U postgres -d htbiz -tAc 'SELECT 1' >/dev/null 2>&1; then
    echo " ready"
    ready=1
    break
  fi
  echo -n "."
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "Database did not become ready within 60 seconds" >&2
  docker logs "$CONTAINER" >&2
  exit 1
fi

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

for migration in "$ROOT"/supabase/migrations/20260930*.sql; do
  run_sql "Feature migration" "$migration"
  run_sql "Feature migration idempotency" "$migration"
done
run_sql "Search, reviews and analytics assertions" "$HERE/03_feature_assertions.sql"

echo
echo "==> All migrations applied and all assertions passed."
