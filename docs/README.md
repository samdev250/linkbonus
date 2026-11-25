# LINK BONUS setup and deployment

## Vercel monorepo import

The repository root contains `vercel.json` for one Vercel multi-service project. On Vercel, import `samdev250/linkbonus` from the repository root and choose the multi-service project option. Do not set a service root directory in the import form; the root config selects `frontend/` and `backend/` and routes `/api/*` to the Express API while sending other paths to the Vite site.

Vercel Services are currently a beta feature and may require access on the account. The root configuration uses the current `services` format. If the multi-service option is unavailable, create two Vercel projects from the same repository: one with Root Directory `frontend`, and one with Root Directory `backend`; see the separate-project steps below.

### Environment variables

Set these values in Vercel Project Settings → Environment Variables for Production and Preview as needed:

- `VITE_SUPABASE_URL` — the Supabase project URL, available to the frontend build.
- `VITE_SUPABASE_PUBLISHABLE_KEY` — the Supabase publishable key, available to the frontend build. This key is public; do not use a secret or service-role key here.
- `SUPABASE_URL` — the same Supabase project URL for the API runtime.
- `SUPABASE_PUBLISHABLE_KEY` — the same publishable key for the API runtime.
- `FRONTEND_ORIGINS` — optional comma-separated frontend origins for cross-origin API use. A single Vercel multi-service project uses same-origin `/api` requests, so this is not needed for ordinary browser calls.

The frontend defaults to `/api` in production. The root service routes send these requests to the backend. Local development keeps the API at `http://localhost:4000/api`.

After Vercel assigns the project URL, add it to Supabase Auth's Site URL and allowed redirect URLs. Enable email confirmation and configure the production redirect URL before inviting members. No Vercel project has been created or deployed from this repository.

### Separate-project import fallback

If Services are unavailable on the Vercel account:

**Frontend project:** Root Directory `frontend`; Framework Preset Vite; Build Command `npm run build`; Output Directory `dist`; set `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, and `VITE_API_URL` to the separately deployed API URL ending in `/api`.

**API project:** Root Directory `backend`; Framework Preset Express; use the backend `npm run build` command and `src/server.ts` entrypoint; set `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `FRONTEND_ORIGINS` to the exact frontend origin.

## Supabase database

1. Create a Supabase project and install the Supabase CLI.
2. From the repository root, authenticate and link the project with `supabase login` and `supabase link --project-ref YOUR_PROJECT_REF`.
3. Apply the versioned schema and seed data with `supabase db push`.
4. In Supabase Auth, configure email confirmation and add the local and production frontend URLs to the allowed site and redirect URL lists.
5. Use the project's URL and publishable key in the frontend and API. Never put a secret/service-role key in frontend variables.

The first migration creates profiles, empty asset accounts, row-level security and read-only member access. The second migration stores signup country and phone. The Auth trigger assigns `referred_by` by looking up the invitation code supplied at signup; invalid or absent codes create an un-referred account. Sample plans are inactive and contain no live financial terms.

## Local development

Copy `frontend/.env.example` to `frontend/.env.local` and set `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, and `VITE_API_URL=http://localhost:4000/api`. Copy `backend/.env.example` to `backend/.env` and set the same project URL and publishable key plus any required API settings.

Install each app and run them in separate terminals:

```sh
npm --prefix backend ci
npm --prefix backend run dev
npm --prefix frontend ci
npm --prefix frontend run dev
```

## Current limits before client financial use

Signup, email confirmation, sign-in, profile provisioning and member data reads are connected to Supabase. Registration offers a searchable ISO country and territory list. Admins can create, search, update and suspend/reactivate user profiles; permanent user deletion is intentionally unavailable to preserve financial and audit history. The admin Users view shows wallet balance, active/pending investment principal, received bonuses, credited referral commissions and portfolio value in the member's account currency. Finance and super-admin roles can add audited wallet credits or separate bonus credits; historical investment and referral amounts remain read-only and are changed only by their existing workflows. Deposits, withdrawals, investments and trading are not implemented. Referral links, signup attribution and one-time 50% commission crediting on the first activated investment are implemented. Twenty RWF investment plans are published for Rwandan members, and Burundian members see the Direct Bonus schedule as information only. Staking has been removed from the database, API and interface. The UI and database intentionally deny client writes to financial tables. Payment-provider integrations, independent review of financial controls, KYC, legal review, monitoring and security review are still required before handling client funds. Do not enable live products or claim returns until those are implemented and reviewed.
