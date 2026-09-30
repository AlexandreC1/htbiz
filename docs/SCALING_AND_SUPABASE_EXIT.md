# HTBiz: optimization and Supabase exit plan

## Recommendation

Keep PostgreSQL. Put a versioned application API between Flutter and backend
services, then migrate database, storage, and identity separately. Replacing
Supabase alone will not fix client-side search or an inefficient query pattern.
There are no measured production throughput or latency figures in this review;
capacity and cost choices must follow measurements, not user-count guesses.

A concrete target to evaluate is an autoscaled container API, managed PostgreSQL
(for example AWS RDS), object storage (for example S3), and a separate identity
provider. Start with one API service and background worker, not microservices.
Use a connection pool, bounded queries, and explicit authorization. Add replicas
or a dedicated analytics store only when load measurements justify them.

## Code findings and priorities

| Priority | Finding | Action |
|---|---|---|
| P0 | Home searched only its first 20 loaded businesses | Server-filtered, debounced, paginated search in this change |
| P0 | Review dialog discarded the draft before persistence | Keep it open on error; transactional save/update RPC; regression coverage |
| P1 | Repeat review submissions collided with unique constraints | Serialize saves by user/business and update the existing review |
| P1 | Dashboard averaged businesses equally and counted capped review lists | Weight by review count and use stored total-review counts |
| P1 | Direct Supabase calls spread across screens and services | Introduce repositories for identity, directory, reviews, media, analytics |
| P1 | Owner dashboards fetch per-business review and favorite data | Replace N+1 requests with an authorized aggregate endpoint |
| P1 | Distance sorting sorts downloaded results, not all businesses | Add indexed spatial search and server-side distance pagination |
| P1 | Analytics adds writes to the transaction database | Measure ingest load; cap events, retain 30 days, move to queue/warehouse as needed |
| P2 | Rating distribution uses up to 100 reviews per business | Replace with SQL aggregate buckets before presenting it as a complete distribution |
| P2 | List queries fetch complete business rows | Introduce compact list DTOs and dedicated detail fetches |

The existing database already had trigram search support. This change adds a
partial index for active businesses, matching the new search predicate. Benchmark
with realistic row counts and `EXPLAIN (ANALYZE, BUFFERS)` before tuning further.
[PostgreSQL trigram documentation](https://www.postgresql.org/docs/17/pgtrgm.html).

## Phased migration

1. **Inventory and baseline.** Export actual production schema and migration
   history; compare them with this repository. Inventory auth users, RLS,
   triggers, RPCs, storage objects, redirects, push tokens, secrets, and edge
   functions. Measure p50/p95 latency, failed writes, DB connections, query cost,
   monthly storage/egress, and event volume. Restore a backup in an isolated
   environment and verify it before any cutover.
2. **Own the API boundary.** Define `/v1/businesses`, `/v1/reviews`, `/v1/media`,
   and `/v1/usage`. Move direct Supabase calls behind Dart repositories. The API
   initially uses existing Supabase data/auth. Verify JWTs server-side, enforce
   ownership/admin rights, add request IDs and idempotency keys, and port every
   RLS/security assertion. Never ship service-role or database credentials in
   Flutter. Support older mobile releases during the transition.
3. **Move storage.** Copy public business/review images and private patent files
   with checksums and object counts. Preserve private authorization. Store object
   keys separately from provider URLs. Use short-lived signed uploads, explicit
   MIME/size validation and CDN delivery. Keep old URLs or a compatibility layer
   until deployed mobile clients have migrated. Test upload, deletion and access.
   [S3 signed URL behavior](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html).
4. **Move PostgreSQL.** Provision staging, backups, pooling, monitoring, and an
   appropriate availability configuration. Map `auth.users` foreign keys to an
   application-owned user table; replace `auth.uid()`, Supabase roles, storage
   helpers, and edge-function dependencies explicitly. Use a rehearsed write
   freeze plus final delta copy, or monitored CDC with a clear source of truth.
   Compare row counts, checksums, review aggregates, permissions, and query plans.
   Do not introduce unsupervised dual writes.
   [RDS Multi-AZ cluster capabilities](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/multi-az-db-clusters-concepts.html),
   [connection proxy behavior](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.howitworks.html).
5. **Move identity last.** Preserve stable application user IDs independently
   of the new provider's subject IDs. Rehearse email/password, anonymous-account
   handling, OAuth, password resets, account deletion and session revocation.
   Validate supported password-hash import or a just-in-time login migration;
   do not assume sessions or passwords can be copied unchanged. Keep an explicit
   fallback/reset flow and migration window.
   [Cognito migration trigger](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-lambda-migrate-user.html),
   [Supabase auth migration considerations](https://supabase.com/docs/guides/troubleshooting/migrating-auth-users-between-projects).
6. **Cut over gradually.** Use a release flag and small client cohort. Proposed
   acceptance gates: zero lost/duplicate reviews under retries, authorization
   parity, successful backup restore, p95 search below an agreed mobile budget,
   and sustained load at twice the measured peak. These are targets, not achieved
   benchmarks. Keep Supabase available through an agreed rollback window.
   Switching back after new writes requires replay/reconciliation, not merely
   changing a URL. Decommission only after auditing data parity and old clients.

## Analytics scope

New analytics are **administrator-only**, per the user's instruction. Business
owners retain their existing business metrics, with no access to usage events.
The current implementation is first-party, opt-in telemetry for signed-in users.
It records account ID, OS/version, logical viewport dimensions, tab views and
foreground time, review media selection, and approximate location when the user
already invokes the location feature. It does not inspect other apps, screen
recordings, photos, contacts, or the user's media library.

Request IP comes from a proxy header and is explicitly marked unverified; confirm
the deployed gateway overwrites that header before using it as a reliable source.
No third-party IP geolocation service is provisioned. Location is rounded GPS
coordinates from the existing user-initiated feature, not an inferred city.
Unknown dimensions remain null. UI hides events older than 30 days; schedule
physical deletion daily. Data volume is capped at 60 events/user/minute, and
analytics failures do not block app operations. Current delivery is best-effort,
without durable buffering, and short sessions/crashes can lose timing data.

## Release steps for this change

1. Run Flutter format/analyze/tests and the isolated database migration suite.
2. Audit and back up the live schema. Apply the two `20260930` migrations **before**
   releasing the new client: it depends on `save_review` and analytics RPCs.
   Repository tests do not prove those functions exist in production.
3. Add the intended administrator's authenticated UUID to `public.admins` using
   a privileged SQL session; never expose a self-service admin promotion path.
4. Schedule `SELECT public.purge_expired_usage();` daily using a privileged job.
   Verify physical deletion, proxy-header provenance, and account deletion.
5. Open Profile → Usage and privacy. Confirm opt-in, withdrawal, deletion, and
   administrator access with separate real accounts. Reopen the app and verify
   ratings remain saved; check poor connectivity and small-screen layouts.
6. Push only task-owned changes, verify GitHub CI, and perform a staging device
   smoke test before production rollout. Existing uncommitted branding changes
   are separate work and must not be included accidentally.
