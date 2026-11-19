import 'dotenv/config';
import express, { type NextFunction, type Request, type Response } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const app = express();
app.use(helmet());
const allowedOrigins = (process.env.FRONTEND_ORIGINS ?? process.env.FRONTEND_ORIGIN ?? 'http://localhost:5173')
  .split(',').map(origin => origin.trim()).filter(Boolean);
app.use(cors({ origin: (origin, callback) => {
  if (!origin || allowedOrigins.includes(origin)) return callback(null, true);
  return callback(new Error('Origin is not allowed by CORS'));
} }));
app.use(express.json({ limit: '32kb' }));

const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_PUBLISHABLE_KEY ?? process.env.SUPABASE_ANON_KEY;
const authClient = url && anonKey ? createClient(url, anonKey, { auth: { persistSession: false } }) : null;
type SessionLocals = { user: { id: string; email?: string }; db: SupabaseClient };
type SessionResponse = Response<unknown, SessionLocals>;
const fail = (res: Response, error: unknown) => {
  console.error('API request failed:', error);
  return res.status(500).json({ error: 'Unable to load requested data' });
};
const minor = (value: unknown) => BigInt(String(value ?? 0));
const amount = (value: bigint) => {
  const sign = value < 0n ? '-' : '';
  const abs = value < 0n ? -value : value;
  return `${sign}${abs / 100n}.${String(abs % 100n).padStart(2, '0')}`;
};

app.get('/api/health', (_req, res) => res.json({ status: 'ok', database: authClient ? 'configured' : 'not_configured', mode: 'test' }));

// Each request gets a Supabase client carrying the verified user's token. RLS
// therefore remains the final boundary for all member reads.
app.use('/api', async (req: Request, res: SessionResponse, next: NextFunction) => {
  if (req.path === '/health') return next();
  if (!authClient || !url || !anonKey) return res.status(503).json({ error: 'Database is not configured' });
  const header = req.header('authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return res.status(401).json({ error: 'Authentication required' });
  try {
    const { data, error } = await authClient.auth.getUser(token);
    if (error || !data.user) return res.status(401).json({ error: 'Invalid session' });
    res.locals.user = { id: data.user.id, email: data.user.email };
    res.locals.db = createClient(url, anonKey, {
      auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: member, error: memberError } = await res.locals.db.from('profiles').select('status').eq('id', data.user.id).maybeSingle();
    if (memberError) return fail(res, memberError);
    if (member?.status === 'suspended') return res.status(403).json({ error: 'Account is suspended' });
    next();
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/dashboard', async (_req, res: SessionResponse) => {
  try {
    const db = res.locals.db;
    const [profile, accounts, tx, investments, staking, commissions] = await Promise.all([
      db.from('profiles').select('full_name,country,phone,verification_status,referral_code').eq('id', res.locals.user.id).maybeSingle(),
      db.from('asset_accounts').select('id,asset_code').eq('owner_id', res.locals.user.id),
      db.from('ledger_transactions').select('id,kind,status,amount_minor,asset_code,description,created_at').eq('owner_id', res.locals.user.id).order('created_at', { ascending: false }).limit(5),
      db.from('investments').select('principal_minor,asset_code,status').eq('owner_id', res.locals.user.id).in('status', ['active','pending']),
      db.from('staking_positions').select('principal_minor,asset_code,status').eq('owner_id', res.locals.user.id).in('status', ['active','pending']),
      db.from('referral_commissions').select('amount_minor,status').eq('referrer_id', res.locals.user.id),
    ]);
    for (const result of [profile, accounts, tx, investments, staking, commissions]) if (result.error) throw result.error;
    const accountRows = accounts.data ?? [];
    const accountIds = accountRows.map(row => row.id);
    const entries = accountIds.length ? await db.from('ledger_entries').select('account_id,amount_minor').in('account_id', accountIds) : { data: [], error: null };
    if (entries.error) throw entries.error;
    const balances = new Map<string, bigint>();
    for (const row of entries.data ?? []) balances.set(row.account_id, (balances.get(row.account_id) ?? 0n) + minor(row.amount_minor));
    const availableUsd = accountRows.filter(row => row.asset_code === 'USD').reduce((sum, row) => sum + (balances.get(row.id) ?? 0n), 0n);
    const usdInvested = (investments.data ?? []).filter(row => row.asset_code === 'USD').reduce((sum, row) => sum + minor(row.principal_minor), 0n);
    const usdStaked = (staking.data ?? []).filter(row => row.asset_code === 'USD').reduce((sum, row) => sum + minor(row.principal_minor), 0n);
    const credited = (commissions.data ?? []).filter(row => row.status === 'credited').reduce((sum, row) => sum + minor(row.amount_minor), 0n);
    const pending = (commissions.data ?? []).filter(row => row.status === 'pending').reduce((sum, row) => sum + minor(row.amount_minor), 0n);
    const transactions = (tx.data ?? []).map(row => ({
      id: row.id, label: row.kind.replaceAll('_', ' ').replace(/\b\w/g, char => char.toUpperCase()),
      detail: row.description ?? row.asset_code, amount: `${row.kind === 'deposit' || row.kind === 'referral_commission' ? '+' : '−'} ${row.asset_code} ${amount(minor(row.amount_minor))}`,
      date: row.created_at, status: row.status,
    }));
    const name = profile.data?.full_name || res.locals.user.email?.split('@')[0] || 'Member';
    return res.json({ data: {
      name, email: res.locals.user.email ?? '', currency: 'USD',
      available: amount(availableUsd), invested: amount(usdInvested), staked: amount(usdStaked),
      referrals: amount(credited), pendingReferrals: amount(pending),
      portfolio: amount(availableUsd + usdInvested + usdStaked), transactions,
      profile: profile.data ?? null, verifiedPerformance: false,
    } });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/transactions', async (req, res: SessionResponse) => {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 25, 1), 100);
    const { data, error } = await res.locals.db.from('ledger_transactions').select('id,kind,status,amount_minor,asset_code,provider_reference,description,created_at,completed_at').eq('owner_id', res.locals.user.id).order('created_at', { ascending: false }).limit(limit);
    if (error) throw error;
    return res.json({ data: (data ?? []).map(row => ({ ...row, amount: amount(minor(row.amount_minor)) })) });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/wallet', async (_req, res: SessionResponse) => {
  try {
    const { data: accounts, error } = await res.locals.db.from('asset_accounts').select('id,asset_code').eq('owner_id', res.locals.user.id);
    if (error) throw error;
    const rows = accounts ?? [];
    const entries = rows.length ? await res.locals.db.from('ledger_entries').select('account_id,amount_minor').in('account_id', rows.map(row => row.id)) : { data: [], error: null };
    if (entries.error) throw entries.error;
    const sums = new Map<string, bigint>();
    for (const entry of entries.data ?? []) sums.set(entry.account_id, (sums.get(entry.account_id) ?? 0n) + minor(entry.amount_minor));
    return res.json({ data: rows.map(row => ({ asset: row.asset_code, balance: amount(sums.get(row.id) ?? 0n) })) });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/investments', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.from('investments').select('id,principal_minor,asset_code,status,created_at,investment_plans(name,duration_days,fee_bps,risk_disclosure,performance_methodology)').eq('owner_id', res.locals.user.id).order('created_at', { ascending: false });
    if (error) throw error;
    return res.json({ data: (data ?? []).map(row => ({ ...row, principal: amount(minor(row.principal_minor)) })) });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/referrals', async (_req, res: SessionResponse) => {
  try {
    const [profile, commissions, summary] = await Promise.all([
      res.locals.db.from('profiles').select('referral_code').eq('id', res.locals.user.id).maybeSingle(),
      res.locals.db.from('referral_commissions').select('id,invitee_id,amount_minor,status,created_at,credited_at').eq('referrer_id', res.locals.user.id).order('created_at', { ascending: false }),
      res.locals.db.rpc('member_referral_summary'),
    ]);
    for (const result of [profile, commissions, summary]) if (result.error) throw result.error;
    const rows = commissions.data ?? [];
    return res.json({ data: {
      referralCode: profile.data?.referral_code ?? null,
      summary: summary.data,
      commissions: rows.map(row => ({ ...row, amount: amount(minor(row.amount_minor)) })),
    } });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/profile', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.from('profiles').select('id,full_name,country,phone,verification_status,referral_code,created_at').eq('id', res.locals.user.id).maybeSingle();
    if (error) throw error;
    return res.json({ data: { ...data, email: res.locals.user.email } });
  } catch (error) { return fail(res, error); }
});

app.get('/api/investment-plans', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.from('investment_plans').select('id,name,minimum_minor,maximum_minor,duration_days,fee_bps,performance_methodology,risk_disclosure').eq('active', true).order('minimum_minor');
    if (error) throw error;
    return res.json({ data: (data ?? []).map(row => ({ ...row, minimum: amount(minor(row.minimum_minor)), maximum: row.maximum_minor == null ? null : amount(minor(row.maximum_minor)) })) });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/overview', (_req, res) => res.status(503).json({ error: 'Admin reporting service requires audited admin authorization and aggregate RPCs' }));
app.use('/api/admin', (_req, res) => res.status(503).json({ error: 'Admin management service is not configured' }));
app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

// Vercel detects this exported Express app and serves it as a serverless function.
export default app;

// Keep the same module usable by local Node development.
if (process.env.VERCEL !== '1') {
  const port = Number(process.env.PORT) || 4000;
  app.listen(port, () => console.log(`LINK BONUS API listening on ${port} (test mode)`));
}
