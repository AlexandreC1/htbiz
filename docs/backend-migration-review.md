# HTBIZ backend and Google sign-in review

## Finding: Google sign-in is blocked by project configuration

The Android auth log for the previously configured backend recorded Supabase returning `provider_disabled` after the Google native flow. That means Google produced a credential and the request reached Supabase Auth; that backend was rejecting Google because its Google provider was disabled. The Flutter app already calls `signInWithIdToken` for native sign-in and uses Supabase OAuth for web sign-in. This points to provider configuration as the known failure, not evidence that the app needs a different database.

On the replacement hosted project, check/enable Google under Authentication → Sign In / Providers. The provider needs an OAuth Web client ID and secret from Google Cloud; Google must allow that Supabase project's Auth callback URL. Verify the Android app's package/SHA fingerprints in the Google OAuth client as well. The Supabase docs require the provider setup for both native ID-token and browser OAuth flows: <https://supabase.com/docs/guides/auth/social-login/auth-google>.

The dashboard UI could not be opened because no authenticated browser session is available. A signed-in Supabase CLI session provided Management API access. Do not put a service-role key in Flutter, GitHub Actions, or chat to work around dashboard access. The service-role key previously pasted into chat should be rotated.

Live verification on 2026-10-05 found the replacement project `lvpzccrzxymemlxurbnx` is active and initially had Google disabled with no client ID or secret. The inactive original HTBIZ project contained a complete Google OAuth client configuration; its client ID matches the one used by the app. I copied those existing provider credentials securely through the authenticated Management API and enabled Google on the active project. The active Auth settings now report `external.google = true`, and a read-only authorization request returns a Google redirect whose callback URI is the active project's `/auth/v1/callback`. A deliberately invalid native ID token returned HTTP 400, but the response body was unavailable, so it does not prove successful native token exchange. The already-installed debug APK on the connected TECNO device was confirmed to contain the active Supabase project URL and launched; its display remained on the splash screen, so no Google account was selected. A deadline was added around splash deep-link and profile lookups to prevent indefinite startup waits; this source change has not been rebuilt onto the phone yet. The GitHub Actions secret-name listing contains only `SUPABASE_URL` and `SUPABASE_ANON_KEY`, and the app's `.env` has no Google OAuth secret; the client secret remains only in Supabase Auth settings.

## What a backend replacement affects

The app has roughly 80 direct Supabase SDK call sites across authentication, relational queries, RPCs, storage, and administration. Its backend also includes four tracked SQL migrations, row-level security policies, Postgres functions/triggers, and two Supabase Edge Functions. Firebase Messaging is already present, but Firebase Authentication and Firestore are not.

Consequently, a database-only move does not replace this backend. The replacement must also cover identity and sessions, authorization, database access, object storage, RPC/business logic, push-notification functions, and admin analytics. Every option must be tested for data parity and permissions before production traffic changes.

## Options

| Path | What it solves | Migration cost for HTBIZ | Main tradeoff |
|---|---|---:|---|
| Keep managed Supabase and enable Google | Fixes the current login failure | Very low | Keeps current vendor and hosting |
| Self-host Supabase with Docker Compose | Moves operations and data under your control while retaining the Supabase APIs | Lowest platform-move cost | You own TLS, SMTP, OAuth secrets, upgrades, backups, monitoring, uptime and recovery |
| Appwrite Cloud | Replaces the managed BaaS; its migration tool imports Supabase users, database rows and files | High | Supabase rows migrate only partially; OAuth users must sign in again; Postgres functions, schedules and Edge Functions need manual replacement; data permissions must be rebuilt |
| Firebase Auth + Firestore | Google-native managed identity and database | Highest | Firestore is document/NoSQL, so relational joins, SQL queries, RLS policies, RPCs and storage integration need redesign |
| Firebase Auth with current Supabase data services | Changes the identity provider without moving the Postgres backend | Medium | Requires Supabase third-party Auth integration and `role: authenticated` JWT claims; it does not remove the Supabase database dependency |
| Hosted Postgres (for example Neon) | Replaces only the database host | High | Still needs separate Auth, API/authorization, file storage and function services; not a drop-in replacement for the current client SDK |

Appwrite's own migration guide says Supabase rows are partial, OAuth users are not migrated (they must re-authenticate), and functions are manual. It also warns that some Postgres features such as advanced indexes, functions and scheduling do not transfer: <https://appwrite.io/docs/advanced/migrations/supabase>.

Firebase Authentication is available in Flutter, but must be enabled in Firebase Console. Firestore is document-oriented rather than relational: <https://firebase.google.com/docs/auth/flutter/start> and <https://firebase.google.com/docs/firestore/data-model>.

Supabase can trust Firebase Auth tokens without replacing its data services. That still requires registering the Firebase project and ensuring every Firebase JWT carries the `authenticated` role claim: <https://supabase.com/docs/guides/auth/third-party/firebase-auth>.

## Docker and migration notes

The least disruptive way to leave Supabase's managed hosting is to run Supabase itself on a VPS with the official Docker Compose deployment. The official minimum for the complete stack is 4 GB RAM, 2 CPU cores, and 40 GB SSD; 8 GB+, 4 cores+, and 80 GB+ are recommended. The local Supabase CLI stack is explicitly for development/testing and must not be exposed as production infrastructure. Self-hosting transfers responsibility for secure operations to HTBIZ: <https://supabase.com/docs/guides/self-hosting/docker> and <https://supabase.com/docs/guides/self-hosting>.

Supabase's platform-to-self-host restore includes Postgres schema/data, roles, RLS policies, database functions/triggers, and `auth.users`. It does not migrate OAuth provider configuration, object files, or Edge Functions. Provider settings and SMTP must be recreated, JWT/API keys change (so existing sessions expire), and database/Auth/Storage version mismatches can require restore troubleshooting. Supabase recommends testing the restore before switching traffic: <https://supabase.com/docs/guides/self-hosting/restore-from-platform>.

This repository already has Supabase migrations, Edge Functions, and database security tests, which is a useful foundation for a self-hosted pilot. Its local `supabase/config.toml` does not currently configure Google as an external provider, so the local/container environment would need explicit Google OAuth settings too.

A local pilot was attempted with Supabase CLI 2.119.0 and Docker Compose. Docker Hub returned `registry: Rate exceeded` while pulling the Supabase service images. A follow-up `supabase status` found no HTBIZ database container, so migrations have not yet been exercised in containers. Docker and Compose are installed; Docker access works with approval. The pilot can be retried after Docker Hub access is available (for example, after signing in to Docker Hub) or after its pull limit resets.

The current local Supabase CLI metadata is linked to the old project ref `mgamhhssdmeripqdkogs`, while the app's `.env` points to the replacement project `lvpzccrzxymemlxurbnx`. The CLI is available through `npx` but the local link has not been repaired. Before running any CLI command that reads from or writes to a remote project, explicitly relink it to the intended ref and verify the target shown by the CLI. Do not run `db push` or a data migration while this mismatch remains.

## Recommended sequence

1. The provider configuration fix is applied to the replacement project. Complete one real Google account sign-in on the phone, then check the Google Cloud OAuth client's authorized callback list for the active project's callback URL, especially for browser sign-in.
2. If avoiding managed Supabase is a firm requirement, validate an isolated Docker Compose self-hosted restore as the lowest-rewrite migration. Compare row counts, auth users, RLS tests, stored files, Edge Function behavior, email confirmation/reset, Google sign-in and push notifications before considering a cutover.
3. Choose Appwrite only if a full BaaS rewrite is acceptable and a cloud-managed alternative matters more than preserving Postgres/RLS semantics. Choose Firebase only if committing to a deliberate Firestore data-model rewrite is acceptable.
4. Keep the existing project live until the candidate backend passes the same security and functional tests. A migration of stored rows alone is not proof that authorization or account sign-in works.
