# RLS and database security — CrashGuard AI

Snapshot of **public** tables in `supabase/migrations/` and their access pattern. Re-run this audit when adding migrations.

## Tables (by migration file)

| Table | RLS | Policies (summary) | Client access |
|-------|-----|---------------------|---------------|
| `emergency_facilities` | On | `anon, authenticated` **SELECT** all rows | PowerSync read replica; data from `sync-osm-facilities` (service role) |
| `reported_incidents` | On | **SELECT/INSERT/UPDATE** own rows (`auth.uid() = user_id`) | Authenticated user incidents |
| `incident_live_links` | On | **INSERT/UPDATE** own; **no public SELECT** | Family views via `family-track` Edge Function (service role) |
| `crash_config` | On | `anon, authenticated` **SELECT** all | Read-only remote config for app |
| `crash_config_regions` | On | `anon, authenticated` **SELECT** active rows (`20260502000001`) | GPS bounding boxes → zone mapping for thresholds |

## Edge Functions (secrets)

- **Triage / SMS / OSM sync** must use **Supabase secrets** (`GEMMA_API_KEY`, Twilio, etc.) — never commit keys.
- Triage entrypoint enforces **request size limits** (see `triage-gemini/index.ts`) to reduce abuse and OOM.
- **Rate limiting** at the edge (per-IP / per-user) is **recommended** for production; use Supabase + gateway or WAF when scaling.

## Logging (PII)

- Do not log **raw GPS**, **full phone numbers**, or **medical transcript** in client or Edge logs in production.
- `TriageValidationAgent` logs **override reasons** without coordinates — keep that pattern.
- Truncate third-party API error bodies in Edge responses (implemented in `triage-gemini`).

## Action list for new features

1. `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`
2. Least-privilege policies for `anon` vs `authenticated` vs service role.
3. No sensitive reads through **anon** PostgREST unless intentionally public and non-PII.
