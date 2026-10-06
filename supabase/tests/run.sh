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
run_sql "Reconciling the dashboard-created schema" \
        "$ROOT/supabase/migrations/20260415000000_reconcile_live_schema.sql"
run_sql "Schema reconciliation idempotency" \
        "$ROOT/supabase/migrations/20260415000000_reconcile_live_schema.sql"
run_sql "Full base migration"              "$ROOT/supabase/migrations/20260415010000_full_schema.sql"
run_sql "20260416_push_notifications.sql"  "$ROOT/supabase/migrations/20260416_push_notifications.sql"
run_sql "Push notifications idempotency"  "$ROOT/supabase/migrations/20260416_push_notifications.sql"
run_sql "20260902000000_production_hardening.sql" \
        "$ROOT/supabase/migrations/20260902000000_production_hardening.sql"

# Re-apply the hardening migration: it must be safe to run twice.
run_sql "Re-running hardening (idempotency check)" \
        "$ROOT/supabase/migrations/20260902000000_production_hardening.sql"

run_sql "Profile onboarding RLS" \
        "$ROOT/supabase/migrations/20261005000000_profile_onboarding_rls.sql"
run_sql "Profile onboarding RLS idempotency" \
        "$ROOT/supabase/migrations/20261005000000_profile_onboarding_rls.sql"
run_sql "Profile privacy and role validation" \
        "$ROOT/supabase/migrations/20261007000000_profile_privacy_and_roles.sql"
run_sql "Profile privacy and role validation idempotency" \
        "$ROOT/supabase/migrations/20261007000000_profile_privacy_and_roles.sql"

run_sql "Security assertions" "$HERE/02_security_assertions.sql"

for migration in "$ROOT"/supabase/migrations/20260930*.sql; do
  run_sql "Feature migration" "$migration"
  run_sql "Feature migration idempotency" "$migration"
done
run_sql "Search, reviews and analytics assertions" "$HERE/03_feature_assertions.sql"
run_sql "Orphaned business owner notification guard" \
        "$ROOT/supabase/migrations/20261006000000_review_notification_orphan_guard.sql"
run_sql "Orphaned business owner rating rollups" \
        "$ROOT/supabase/migrations/20261006010000_orphan_owner_rating_rollups.sql"
run_sql "Orphaned owner rating rollups idempotency" \
        "$ROOT/supabase/migrations/20261006010000_orphan_owner_rating_rollups.sql"
run_sql "Orphaned owner rating regression" "$HERE/04_orphan_owner_rating_assertion.sql"
run_sql "Stale rating aggregate seed" "$HERE/05_rating_resync_seed.sql"
run_sql "Rating aggregate resync" \
        "$ROOT/supabase/migrations/20261006020000_resync_rating_rollups.sql"
run_sql "Rating aggregate resync idempotency" \
        "$ROOT/supabase/migrations/20261006020000_resync_rating_rollups.sql"
run_sql "Rating aggregate resync assertions" "$HERE/05_rating_resync_assertion.sql"
run_sql "Legacy dashboard policies" "$HERE/06_legacy_policies_seed.sql"
run_sql "Dropping legacy dashboard policies" \
        "$ROOT/supabase/migrations/20261006030000_drop_legacy_dashboard_policies.sql"
run_sql "Dropping legacy dashboard policies idempotency" \
        "$ROOT/supabase/migrations/20261006030000_drop_legacy_dashboard_policies.sql"
run_sql "Legacy policy assertions" "$HERE/06_legacy_policies_assertion.sql"

echo
echo "==> All migrations applied and all assertions passed."
