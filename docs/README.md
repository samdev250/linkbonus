# LINK BONUS setup and deployment

## Supabase database

1. Create a Supabase project and install the Supabase CLI.
2. From the repository root, authenticate and link the project with `supabase login` and `supabase link --project-ref YOUR_PROJECT_REF`.
3. Apply the versioned schema and seed data with `supabase db push`.
4. In Supabase Auth, configure email confirmation and add the local and production frontend URLs to the allowed site and redirect URL lists.
5. Use the project's URL and **publishable key** (`sb_publishable_...`) in the frontend. The publishable key is public by design; row-level security remains enabled. Do not put the secret/service-role key in frontend variables.

The first migration creates profiles, empty asset accounts, row-level security and read-only member access. The second migration stores signup country and phone. The Auth trigger assigns `referred_by` by looking up the invitation code supplied at signup; invalid or absent codes create an un-referred account. Sample plans are inactive and contain no live financial terms.

## Local development

Copy `frontend/.env.example` to `frontend/.env.local` and set `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, and `VITE_API_URL=http://localhost:4000/api`. Copy `backend/.env.example` to `backend/.env` and set the same project URL and publishable key.

Install each app and run them in separate terminals:

```sh
npm --prefix backend install
npm --prefix backend run dev
npm --prefix frontend install
npm --prefix frontend run dev
```

## Vercel deployment

Deploy the frontend and API as two Vercel projects from the same Git repository:

### Frontend project

- Root Directory: `frontend`
- Framework: Vite
- Build command: `npm run build`
- Output directory: `dist`
- Environment variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, and `VITE_API_URL=https://YOUR-API-DOMAIN.vercel.app/api`

### API project

- Root Directory: `backend`
- Framework: Express (Vercel detects the exported Express application)
- Build command: `npm run build`
- Environment variables: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `FRONTEND_ORIGINS` with the exact production frontend origin. Add a preview origin only if previews should access the API.
- After the first deploy, set the frontend's `VITE_API_URL` to this API project's `/api` URL and redeploy the frontend.

The API verifies each Supabase bearer token and reads member data using a client scoped to that user's token, so database RLS still applies. No Supabase secret/service-role key is needed by the current read-only API. Health check: `https://YOUR-API-DOMAIN.vercel.app/api/health`.

## Current limits before client financial use

Signup, email confirmation, sign-in, profile provisioning and member data reads are connected to Supabase. Deposits, withdrawals, investments, trading, staking settlements and referral credits are not implemented. The UI and database intentionally deny client writes to financial tables. Payment-provider integrations, audited transactional RPCs, administrator authorization, KYC, legal review, monitoring and security review are still required before handling client funds. Do not enable live products or claim returns until those are implemented and reviewed.
