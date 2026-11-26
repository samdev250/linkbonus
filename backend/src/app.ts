import express, { type NextFunction, type Request, type Response } from 'express';
import { randomUUID } from 'node:crypto';
import cors from 'cors';
import helmet from 'helmet';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const app = express();
app.use(helmet());
const allowedOrigins = (process.env.FRONTEND_ORIGINS ?? process.env.FRONTEND_ORIGIN ?? 'http://localhost:5173')
  .split(',').map(origin => origin.trim()).filter(Boolean);
allowedOrigins.push('https://linkbonus.vercel.app');
app.use(cors({ origin: (origin, callback) => {
  if (!origin || allowedOrigins.includes(origin)) return callback(null, true);
  return callback(new Error('Origin is not allowed by CORS'));
} }));
app.use(express.json({ limit: '32kb' }));

const clean = (value?: string) => (value ?? '').trim().replace(/^["']|["']$/g, '');
const configuredUrl = clean(process.env.SUPABASE_URL);
const configuredKey = clean(process.env.SUPABASE_PUBLISHABLE_KEY ?? process.env.SUPABASE_ANON_KEY);
const url = /^https?:\/\/\S+$/i.test(configuredUrl) ? configuredUrl : '';
const anonKey = configuredKey;
let authClient: SupabaseClient | null = null;
if (url && anonKey) {
  try { authClient = createClient(url, anonKey, { auth: { persistSession: false } }); }
  catch { authClient = null; }
}
type SessionLocals = { user: { id: string; email?: string; country?: string }; db: SupabaseClient };
type SessionResponse = Response<unknown, SessionLocals>;
const fail = (res: Response, error: unknown) => {
  const code = (error as { code?: string } | null)?.code;
  const message = (error as { message?: string } | null)?.message;
  if (code === 'PGRST202' || code === '42883') {
    return res.status(503).json({ error: 'A required database function is missing. Run the latest Supabase migration.' });
  }
  if (code === '42703' || code === 'PGRST204') {
    return res.status(503).json({ error: 'The database schema is missing required fields. Apply the latest Supabase migrations.' });
  }
  if (code === 'P0001' && message) return res.status(400).json({ error: message });
  console.error('API request failed:', error);
  return res.status(500).json({ error: 'Unable to load requested data' });
};
const minor = (value: unknown) => BigInt(String(value ?? 0));
const amount = (value: bigint) => {
  const sign = value < 0n ? '-' : '';
  const abs = value < 0n ? -value : value;
  return `${sign}${abs / 100n}.${String(abs % 100n).padStart(2, '0')}`;
};
const parseAmountMinor = (value: unknown, allowZero = false) => {
  const amountText = String(value ?? '').trim();
  if (!/^(?:0|[1-9]\d*)(?:\.\d{1,2})?$/.test(amountText)) return null;
  const [whole, fraction = ''] = amountText.split('.');
  const amountMinor = BigInt(whole) * 100n + BigInt(fraction.padEnd(2, '0'));
  return (allowZero ? amountMinor >= 0n : amountMinor > 0n) && amountMinor <= 9223372036854775807n ? amountMinor : null;
};
const countryCurrencyMap = import('country-to-currency').then(module => module.default);
const currencyForCountry = async (country?: string) => {
  const code = (country ?? '').trim().toUpperCase();
  const countryCode = code === 'RWANDA' ? 'RW' : code === 'BURUNDI' ? 'BI' : code;
  const mapping = await countryCurrencyMap;
  return mapping[countryCode as keyof typeof mapping] ?? 'USD';
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
    res.locals.user = { id: data.user.id, email: data.user.email, country: String(data.user.user_metadata?.country ?? '') };
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
    const { error: syncError } = await db.rpc('member_sync_roi', { p_limit: 20 });
    if (syncError) throw syncError;
    const [profile, accounts, tx, investments, commissions, bonusCredits] = await Promise.all([
      db.from('profiles').select('full_name,country,phone,verification_status,referral_code').eq('id', res.locals.user.id).maybeSingle(),
      db.from('asset_accounts').select('id,asset_code').eq('owner_id', res.locals.user.id),
      db.from('ledger_transactions').select('id,kind,status,amount_minor,asset_code,description,created_at').eq('owner_id', res.locals.user.id).order('created_at', { ascending: false }).limit(5),
      db.from('investments').select('principal_minor,asset_code').eq('owner_id', res.locals.user.id).in('status', ['active','pending']),
      db.from('referral_commissions').select('amount_minor,status').eq('referrer_id', res.locals.user.id),
      db.from('ledger_transactions').select('id,kind').eq('owner_id', res.locals.user.id).in('kind', ['bonus_credit','bonus_debit']).eq('status', 'completed'),
    ]);
    for (const result of [profile, accounts, tx, investments, commissions, bonusCredits]) if (result.error) throw result.error;
    const accountRows = accounts.data ?? [];
    const accountIds = accountRows.map(row => row.id);
    const entries = accountIds.length ? await db.from('ledger_entries').select('account_id,amount_minor,transaction_id').in('account_id', accountIds) : { data: [], error: null };
    if (entries.error) throw entries.error;
    const balances = new Map<string, bigint>();
    for (const row of entries.data ?? []) balances.set(row.account_id, (balances.get(row.account_id) ?? 0n) + minor(row.amount_minor));
    const preferredCurrency = await currencyForCountry(profile.data?.country || res.locals.user.country);
    if (!accountRows.some(row => row.asset_code === preferredCurrency)) {
      throw new Error(`Missing ${preferredCurrency} wallet. Apply the local-currency migration.`);
    }
    const currency = preferredCurrency;
    const availableBalance = accountRows.filter(row => row.asset_code === currency).reduce((sum, row) => sum + (balances.get(row.id) ?? 0n), 0n);
    const assetBalances = accountRows.map(row => ({ asset: row.asset_code, balance: amount(balances.get(row.id) ?? 0n) }));
    const { data: investedAdjustments, error: investedAdjustmentsError } = await db.from('admin_invested_adjustments')
      .select('delta_minor').eq('owner_id', res.locals.user.id).eq('asset_code', currency);
    if (investedAdjustmentsError) throw investedAdjustmentsError;
    const invested = (investments.data ?? []).filter(row => row.asset_code === currency).reduce((sum, row) => sum + minor(row.principal_minor), 0n)
      + (investedAdjustments ?? []).reduce((sum, row) => sum + minor(row.delta_minor), 0n);
    const credited = (commissions.data ?? []).filter(row => row.status === 'credited').reduce((sum, row) => sum + minor(row.amount_minor), 0n);
    const pending = (commissions.data ?? []).filter(row => row.status === 'pending').reduce((sum, row) => sum + minor(row.amount_minor), 0n);
    const bonusTransactionIds = new Set((bonusCredits.data ?? []).map(row => row.id));
    const currencyAccountIds = new Set(accountRows.filter(row => row.asset_code === currency).map(row => row.id));
    const bonus = (entries.data ?? []).filter(row => currencyAccountIds.has(row.account_id) && bonusTransactionIds.has(row.transaction_id))
      .reduce((sum, row) => sum + minor(row.amount_minor), 0n);
    const transactions = (tx.data ?? []).map(row => ({
      id: row.id, label: row.kind.replaceAll('_', ' ').replace(/\b\w/g, (char: string) => char.toUpperCase()),
      detail: row.description ?? row.asset_code, amount: `${row.kind === 'deposit' || row.kind === 'referral_commission' || row.kind === 'bonus_credit' || row.kind === 'wallet_credit' ? '+' : '−'} ${row.asset_code} ${amount(minor(row.amount_minor))}`,
      date: row.created_at, status: row.status,
    }));
    const { data: roiData, error: roiError } = await db.rpc('member_roi_summary');
    if (roiError) throw roiError;
    const name = profile.data?.full_name || res.locals.user.email?.split('@')[0] || 'Member';
    return res.json({ data: {
      name, email: res.locals.user.email ?? '', currency,
      available: amount(availableBalance), invested: amount(invested), bonus: amount(bonus),
      referrals: amount(credited), pendingReferrals: amount(pending),
      portfolio: amount(availableBalance + invested), assetBalances, transactions,
      profile: profile.data ?? null, verifiedPerformance: false, returns: roiData ?? null,
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
    const { data, error } = await res.locals.db.from('investments').select('id,principal_minor,asset_code,status,created_at,roi_rate_bps,total_roi_paid_minor,next_roi_at,creation_source,admin_funding_method,investment_plans(name)').eq('owner_id', res.locals.user.id).in('status', ['active','completed']).order('created_at', { ascending: false });
    if (error) throw error;
    return res.json({ data: (data ?? []).map(row => ({
      id: row.id,
      plan: row.investment_plans?.[0]?.name ?? 'Investment',
      principal_minor: row.principal_minor,
      asset_code: row.asset_code,
      status: row.status,
      rate_bps: row.roi_rate_bps,
      paid_minor: row.total_roi_paid_minor,
      next_roi_at: row.next_roi_at,
      creation_source: row.creation_source,
      admin_funding_method: row.admin_funding_method,
      principal: amount(minor(row.principal_minor)),
    })) });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/referrals', async (_req, res: SessionResponse) => {
  try {
    const [profile, summary] = await Promise.all([
      res.locals.db.from('profiles').select('referral_code').eq('id', res.locals.user.id).maybeSingle(),
      res.locals.db.rpc('member_referral_summary'),
    ]);
    for (const result of [profile, summary]) if (result.error) throw result.error;
    const rows = summary.data?.commission_rows;
    if (!Array.isArray(rows)) throw new Error('Currency-aware referral summary is unavailable. Run the latest Supabase migration.');
    return res.json({ data: {
      referralCode: profile.data?.referral_code ?? null,
      summary: summary.data,
      commissions: rows.map((row: any) => ({ ...row, amount: `${row.asset_code} ${amount(minor(row.amount_minor))}` })),
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
    const profile = await res.locals.db.from('profiles').select('country').eq('id', res.locals.user.id).maybeSingle();
    if (profile.error) throw profile.error;
    const country = (res.locals.user.country || profile.data?.country || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
    const countryFilter = country ? `country_code.is.null,country_code.eq.${country}` : 'country_code.is.null';
    const { data, error } = await res.locals.db.from('investment_plans')
      .select('id,name,minimum_minor,maximum_minor,duration_days,fee_bps,roi_rate_bps,roi_interval_hours,settlement_asset_code,country_code,performance_methodology,risk_disclosure')
      .eq('active', true).or(countryFilter).order('minimum_minor');
    if (error) throw error;
    return res.json({ data: (data ?? []).map(row => ({ ...row, minimum: amount(minor(row.minimum_minor)), maximum: row.maximum_minor == null ? null : amount(minor(row.maximum_minor)) })) });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/returns', async (_req, res: SessionResponse) => {
  try {
    const db = res.locals.db;
    const { error: syncError } = await db.rpc('member_sync_roi', { p_limit: 20 });
    if (syncError) throw syncError;
    const { data, error } = await db.rpc('member_roi_summary');
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/invitations', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('member_list_invitations');
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/member/invitations', async (req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('member_create_invitation', { p_email: String(req.body?.email ?? '') });
    if (error) return fail(res, error);
    return res.status(201).json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/member/invitations/accept', async (req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('accept_invitation', { p_token: String(req.body?.token ?? '') });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/payment-proofs', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('member_list_payment_proofs');
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/member/payment-proofs', async (req, res: SessionResponse) => {
  try {
    const body = req.body ?? {};
    const { data, error } = await res.locals.db.rpc('submit_payment_proof', {
      p_amount_minor: Number(body.amount_minor),
      p_asset_code: String(body.asset_code ?? ''),
      p_screenshot_path: String(body.screenshot_path ?? ''),
      p_phone: String(body.phone ?? ''),
      p_full_name: String(body.full_name ?? ''),
      p_payer_name: String(body.payer_name ?? ''),
      p_idempotency_key: String(body.idempotency_key ?? randomUUID()),
      p_plan_id: body.plan_id || null,
      p_provider_reference: body.provider_reference || null,
      p_note: body.note || null,
      p_payee_name: body.payee_name || null,
    });
    if (error) return fail(res, error);
    return res.status(201).json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/support-settings', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('member_support_settings');
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/payment-instructions', async (req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('member_get_payment_instruction', {
      p_country_code: String(req.query.country ?? '') || null,
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/notifications', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('member_list_notifications');
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/member/notifications/:id/read', async (req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('member_mark_notification_read', { p_id: req.params.id });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.use('/api/admin', async (_req, res: SessionResponse, next) => {
  try {
    const { data, error } = await res.locals.db.rpc('is_admin');
    if (error || data !== true) return res.status(403).json({ error: 'Administrator access required' });
    next();
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/overview', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('admin_overview');
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/referrals', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('admin_referral_list');
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/referral-candidates', async (req, res: SessionResponse) => {
  try {
    const search = String(req.query.search ?? '').trim().slice(0, 120);
    const { data, error } = await res.locals.db.rpc('admin_list_referral_candidates', {
      p_search: search,
      p_limit: Math.min(Math.max(Number(req.query.limit) || 100, 1), 200),
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/referrals/manual', async (req, res: SessionResponse) => {
  try {
    const amountMinor = parseAmountMinor(req.body?.amount);
    if (amountMinor === null) {
      return res.status(400).json({ error: 'Enter a positive commission amount up to two decimal places' });
    }
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    const inviteeId = String(req.body?.invitee_id ?? '');
    if (!uuidPattern.test(inviteeId)) return res.status(400).json({ error: 'Choose a valid referred member' });
    const requestId = String(req.body?.request_id ?? '');
    if (!uuidPattern.test(requestId)) return res.status(400).json({ error: 'Invalid commission request identifier' });
    const reason = String(req.body?.reason ?? '').trim();
    if (!reason || reason.length > 500) return res.status(400).json({ error: 'Enter a reason of up to 500 characters' });

    const { data, error } = await res.locals.db.rpc('admin_grant_referral_commission', {
      p_invitee_id: inviteeId,
      p_amount_minor: amountMinor.toString(),
      p_referral_code: String(req.body?.referral_code ?? ''),
      p_reason: reason,
      p_request_id: requestId.toLowerCase(),
    });
    if (error) return fail(res, error);
    return res.status(201).json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/users', async (req, res: SessionResponse) => {
  try {
    const search = String(req.query.search ?? '').slice(0, 120);
    const status = String(req.query.status ?? 'All users').slice(0, 40);
    const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 200);
    const offset = Math.max(Number(req.query.offset) || 0, 0);
    const { data, error } = await res.locals.db.rpc('admin_list_users', { p_search: search, p_status: status, p_limit: limit, p_offset: offset });
    if (error) return fail(res, error);
    const rows = data?.rows ?? [];
    const userIds = rows.map((row: { id: string }) => row.id);
    const adjustments = userIds.length
      ? await res.locals.db.rpc('admin_user_invested_adjustment_totals', { p_user_ids: userIds })
      : { data: [], error: null };
    if (adjustments.error) return fail(res, adjustments.error);
    const totals = new Map<string, bigint>();
    for (const row of adjustments.data ?? []) {
      const key = `${row.owner_id}:${row.asset_code}`;
      totals.set(key, (totals.get(key) ?? 0n) + minor(row.delta_minor));
    }
    return res.json({ data: {
      ...data,
      rows: rows.map((row: { id: string; balance_asset_code: string; balance_minor: string|number; invested_minor: string|number }) => {
        const invested = minor(row.invested_minor) + (totals.get(`${row.id}:${row.balance_asset_code}`) ?? 0n);
        return { ...row, invested_minor: invested.toString(), portfolio_minor: (minor(row.balance_minor) + invested).toString() };
      }),
    } });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/users/:id/bonus', async (req, res: SessionResponse) => {
  try {
    const amountMinor = parseAmountMinor(req.body?.amount);
    if (amountMinor === null) return res.status(400).json({ error: 'Enter a positive amount up to two decimal places' });
    const requestId = String(req.body?.request_id ?? '');
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestId)) {
      return res.status(400).json({ error: 'Invalid bonus request identifier' });
    }
    const { data, error } = await res.locals.db.rpc('admin_credit_bonus', {
      p_user_id: req.params.id,
      p_amount_minor: amountMinor.toString(),
      p_asset_code: String(req.body?.asset_code ?? ''),
      p_reason: String(req.body?.reason ?? ''),
      p_idempotency_key: `admin-bonus:${requestId.toLowerCase()}`,
    });
    if (error) return fail(res, error);
    return res.status(201).json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/users/:id/wallet-credit', async (req, res: SessionResponse) => {
  try {
    const amountMinor = parseAmountMinor(req.body?.amount);
    if (amountMinor === null) return res.status(400).json({ error: 'Enter a positive amount up to two decimal places' });
    const requestId = String(req.body?.request_id ?? '');
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestId)) {
      return res.status(400).json({ error: 'Invalid wallet credit request identifier' });
    }
    const { data, error } = await res.locals.db.rpc('admin_credit_wallet', {
      p_user_id: req.params.id,
      p_amount_minor: amountMinor.toString(),
      p_asset_code: String(req.body?.asset_code ?? ''),
      p_reason: String(req.body?.reason ?? ''),
      p_idempotency_key: `admin-wallet:${requestId.toLowerCase()}`,
    });
    if (error) return fail(res, error);
    return res.status(201).json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/users', async (req, res) => {
  try {
    const email = String(req.body?.email ?? '').trim().toLowerCase();
    const password = String(req.body?.password ?? '');
    const full_name = String(req.body?.full_name ?? '').trim();
    const country = String(req.body?.country ?? '').trim();
    if (!/^\S+@\S+\.\S+$/.test(email)) return res.status(400).json({ error: 'A valid email address is required' });
    if (password.length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters' });
    const { data, error } = await authClient!.auth.signUp({ email, password, options: { data: { full_name, country } } });
    if (error) return fail(res, error);
    return res.status(201).json({ data: { id: data.user?.id ?? null, email: data.user?.email ?? email, sessionCreated: Boolean(data.session) } });
  } catch (error) { return fail(res, error); }
});

app.patch('/api/admin/users/:id', async (req, res: SessionResponse) => {
  try {
    const walletTargetMinor = parseAmountMinor(req.body?.wallet_target, true);
    const bonusTargetMinor = parseAmountMinor(req.body?.bonus_target, true);
    if (walletTargetMinor === null || bonusTargetMinor === null) {
      return res.status(400).json({ error: 'Enter valid wallet and bonus totals with up to two decimal places' });
    }
    const requestId = String(req.body?.request_id ?? '');
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestId)) {
      return res.status(400).json({ error: 'Invalid user update request identifier' });
    }
    const { data, error } = await res.locals.db.rpc('admin_update_user_account', {
      p_id: req.params.id,
      p_full_name: String(req.body?.full_name ?? ''),
      p_country: String(req.body?.country ?? ''),
      p_phone: String(req.body?.phone ?? ''),
      p_status: String(req.body?.status ?? 'active'),
      p_verification_status: String(req.body?.verification_status ?? 'unverified'),
      p_asset_code: String(req.body?.asset_code ?? ''),
      p_wallet_target_minor: walletTargetMinor.toString(),
      p_bonus_target_minor: bonusTargetMinor.toString(),
      p_reason: String(req.body?.reason ?? 'Admin user update'),
      p_request_id: requestId.toLowerCase(),
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.patch('/api/admin/users/:id/invested', async (req, res: SessionResponse) => {
  try {
    const targetMinor = parseAmountMinor(req.body?.target_amount, true);
    if (targetMinor === null) {
      return res.status(400).json({ error: 'Enter a valid invested total with up to two decimal places' });
    }
    const requestId = String(req.body?.request_id ?? '');
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestId)) {
      return res.status(400).json({ error: 'Invalid invested total update request identifier' });
    }
    const { data, error } = await res.locals.db.rpc('admin_set_user_invested_total', {
      p_user_id: req.params.id,
      p_target_minor: targetMinor.toString(),
      p_asset_code: String(req.body?.asset_code ?? ''),
      p_request_id: requestId.toLowerCase(),
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/users/:id/investments', async (req, res: SessionResponse) => {
  try {
    const principalMinor = parseAmountMinor(req.body?.amount);
    if (principalMinor === null) {
      return res.status(400).json({ error: 'Enter a positive investment amount up to two decimal places' });
    }
    const planId = String(req.body?.plan_id ?? '');
    const requestId = String(req.body?.request_id ?? '');
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidPattern.test(planId)) return res.status(400).json({ error: 'Choose a valid investment plan' });
    if (!uuidPattern.test(requestId)) return res.status(400).json({ error: 'Invalid investment request identifier' });
    const { data, error } = await res.locals.db.rpc('admin_create_investment', {
      p_user_id: req.params.id,
      p_plan_id: planId,
      p_principal_minor: principalMinor.toString(),
      p_request_id: requestId.toLowerCase(),
    });
    if (error) return fail(res, error);
    return res.status(201).json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/users/:id/investments', async (req, res: SessionResponse) => {
  try {
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidPattern.test(req.params.id)) return res.status(400).json({ error: 'Invalid user identifier' });
    const requestedLimit = Math.trunc(Number(req.query.limit));
    const requestedOffset = Math.trunc(Number(req.query.offset));
    const limit = Number.isFinite(requestedLimit) ? Math.min(Math.max(requestedLimit || 10, 1), 100) : 10;
    const offset = Number.isSafeInteger(requestedOffset) ? Math.min(Math.max(requestedOffset, 0), 2147483647) : 0;
    const { data, error, count } = await res.locals.db.from('investments')
      .select('id,principal_minor,asset_code,status,created_at,creation_source,admin_funding_method,investment_plans(name)', { count: 'exact' })
      .eq('owner_id', req.params.id)
      .order('created_at', { ascending: false })
      .order('id', { ascending: false })
      .range(offset, offset + limit - 1);
    if (error) return fail(res, error);
    return res.json({ data: {
      rows: (data ?? []).map(row => ({
        id: row.id,
        plan: (row as any).investment_plans?.name ?? 'Plan',
        amount: amount(minor(row.principal_minor)),
        principal_minor: row.principal_minor,
        asset_code: row.asset_code,
        status: row.status,
        creation_source: row.creation_source,
        admin_funding_method: row.admin_funding_method,
        date: row.created_at,
      })),
      total: count ?? 0,
      limit,
      offset,
    } });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/users/:id/status', async (req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('admin_set_user_status', {
      p_id: req.params.id,
      p_status: String(req.body?.status ?? ''),
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/transactions', async (req, res: SessionResponse) => {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 100, 1), 200);
    const status = String(req.query.status ?? 'All');
    let query = res.locals.db.from('ledger_transactions')
      .select('id,kind,status,amount_minor,asset_code,provider_reference,description,created_at,owner_id')
      .order('created_at', { ascending: false }).limit(limit);
    if (status === 'Deposits' || status === 'Withdrawals') query = query.eq('kind', status === 'Deposits' ? 'deposit' : 'withdrawal');
    else if (['Pending','Completed','Failed','Reversed'].includes(status)) query = query.eq('status', status.toLowerCase());
    const { data, error } = await query;
    if (error) return fail(res, error);
    const rows = data ?? [];
    const ids = Array.from(new Set(rows.map(row => row.owner_id)));
    const profiles = ids.length ? await res.locals.db.from('profiles').select('id,full_name').in('id', ids) : { data: [], error: null };
    if (profiles.error) return fail(res, profiles.error);
    const names = new Map((profiles.data ?? []).map(row => [row.id, row.full_name]));
    return res.json({ data: rows.map(row => ({
      id: row.id,
      reference: row.provider_reference ?? row.id.slice(0, 8),
      user: names.get(row.owner_id) ?? String(row.owner_id).slice(0, 8),
      type: row.kind,
      amount: amount(minor(row.amount_minor)), amount_minor: row.amount_minor,
      asset_code: row.asset_code,
      date: row.created_at,
      status: row.status,
    })) });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/investments', async (_req, res: SessionResponse) => {
  try {
    const requestedLimit = Math.trunc(Number(_req.query.limit));
    const requestedOffset = Math.trunc(Number(_req.query.offset));
    const limit = Number.isFinite(requestedLimit) ? Math.min(Math.max(requestedLimit || 50, 1), 200) : 50;
    const offset = Number.isSafeInteger(requestedOffset) ? Math.min(Math.max(requestedOffset, 0), 2147483647) : 0;
    const { data, error, count } = await res.locals.db.from('investments')
      .select('id,principal_minor,asset_code,status,created_at,owner_id,creation_source,admin_funding_method,investment_plans(name)', { count: 'exact' })
      .order('created_at', { ascending: false }).order('id', { ascending: false }).range(offset, offset + limit - 1);
    if (error) return fail(res, error);
    const rows = data ?? [];
    const ids = Array.from(new Set(rows.map(row => row.owner_id)));
    const profiles = ids.length ? await res.locals.db.from('profiles').select('id,full_name').in('id', ids) : { data: [], error: null };
    if (profiles.error) return fail(res, profiles.error);
    const names = new Map((profiles.data ?? []).map(row => [row.id, row.full_name]));
    return res.json({ data: {
      rows: rows.map(row => ({
        id: row.id,
        user: names.get(row.owner_id) ?? String(row.owner_id).slice(0, 8),
        plan: (row as any).investment_plans?.name ?? 'Plan',
        amount: amount(minor(row.principal_minor)), principal_minor: row.principal_minor,
        asset_code: row.asset_code,
        status: row.status,
        creation_source: row.creation_source,
        admin_funding_method: row.admin_funding_method,
        date: row.created_at,
      })),
      total: count ?? 0,
      limit,
      offset,
    } });
  } catch (error) { return fail(res, error); }
});

app.patch('/api/admin/investments/:id', async (req, res: SessionResponse) => {
  try {
    const targetMinor = parseAmountMinor(req.body?.amount);
    if (targetMinor === null) return res.status(400).json({ error: 'Enter a positive amount up to two decimal places' });
    const requestId = String(req.body?.request_id ?? '');
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidPattern.test(req.params.id)) return res.status(400).json({ error: 'Invalid investment identifier' });
    if (!uuidPattern.test(requestId)) return res.status(400).json({ error: 'Invalid investment update request identifier' });
    const reason = String(req.body?.reason ?? '').trim() || 'Admin updated investment amount';
    if (reason.length > 500) return res.status(400).json({ error: 'Audit note must be 500 characters or fewer' });

    const { data, error } = await res.locals.db.rpc('admin_update_investment_amount', {
      p_investment_id: req.params.id,
      p_target_minor: targetMinor.toString(),
      p_reason: reason,
      p_request_id: requestId.toLowerCase(),
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.delete('/api/admin/investments/:id', async (req, res: SessionResponse) => {
  try {
    const requestId = String(req.body?.request_id ?? '');
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidPattern.test(req.params.id)) return res.status(400).json({ error: 'Invalid investment identifier' });
    if (!uuidPattern.test(requestId)) return res.status(400).json({ error: 'Invalid investment cancellation request identifier' });
    const reason = String(req.body?.reason ?? '').trim() || 'Admin cancelled investment';
    if (reason.length > 500) return res.status(400).json({ error: 'Audit note must be 500 characters or fewer' });

    const { data, error } = await res.locals.db.rpc('admin_cancel_investment', {
      p_investment_id: req.params.id,
      p_reason: reason,
      p_request_id: requestId.toLowerCase(),
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/payment-proofs', async (req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('admin_list_payment_proofs', {
      p_status: String(req.query.status ?? 'pending'),
      p_limit: Number(req.query.limit ?? 50),
      p_offset: Number(req.query.offset ?? 0),
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/payment-proofs/:id/review', async (req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('admin_review_payment_proof', {
      p_id: req.params.id,
      p_action: String(req.body?.action ?? ''),
      p_note: req.body?.note || null,
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/payment-instructions', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('admin_list_payment_instructions');
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/payment-instructions', async (req, res: SessionResponse) => {
  try {
    const body = req.body ?? {};
    const { data, error } = await res.locals.db.rpc('admin_upsert_payment_instruction', {
      p_country_code: String(body.country_code ?? ''),
      p_bank_name: String(body.bank_name ?? ''),
      p_account_name: String(body.account_name ?? ''),
      p_account_number: String(body.account_number ?? ''),
      p_instructions: String(body.instructions ?? ''),
      p_active: body.active !== false,
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/plans', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('admin_list_plans');
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/plans', async (req, res: SessionResponse) => {
  try {
    const body = req.body ?? {};
    const toMinor = (value: any) => Math.round(Number(value || 0) * 100);
    const { data, error } = await res.locals.db.rpc('admin_upsert_plan', {
      p_id: body.id || null,
      p_name: String(body.name ?? ''),
      p_minimum_minor: toMinor(body.minimum),
      p_maximum_minor: body.maximum === '' || body.maximum == null ? null : toMinor(body.maximum),
      p_duration_days: body.duration_days === '' || body.duration_days == null ? null : Number(body.duration_days),
      p_fee_bps: Math.round(Number(body.fee_percent || 0) * 100),
      p_roi_rate_bps: Math.round(Number(body.roi_percent || 0) * 100),
      p_roi_interval_hours: Number(body.roi_interval_hours || 24),
      p_settlement_asset_code: String(body.settlement_asset_code || 'USD'),
      p_country_code: body.country_code ? String(body.country_code).trim().toUpperCase() : null,
      p_performance_methodology: String(body.performance_methodology ?? ''),
      p_risk_disclosure: String(body.risk_disclosure ?? ''),
      p_active: body.active !== false,
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.get('/api/admin/notifications', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('admin_list_notifications');
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/notifications', async (req, res: SessionResponse) => {
  try {
    const body = req.body ?? {};
    const { data, error } = await res.locals.db.rpc('admin_create_notification', {
      p_title: String(body.title ?? ''),
      p_body: String(body.body ?? ''),
      p_audience: String(body.audience ?? ''),
      p_country_code: body.country_code || null,
      p_user_email: body.user_email || null,
    });
    if (error) return fail(res, error);
    return res.status(201).json({ data });
  } catch (error) { return fail(res, error); }
});

app.post('/api/admin/support-settings', async (req, res: SessionResponse) => {
  try {
    const body = req.body ?? {};
    const { data, error } = await res.locals.db.rpc('admin_update_support_settings', {
      p_email: String(body.support_email ?? ''),
      p_whatsapp: body.whatsapp_url || null,
      p_telegram: body.telegram_url || null,
    });
    if (error) return fail(res, error);
    return res.json({ data });
  } catch (error) { return fail(res, error); }
});

app.use('/api/admin', (_req, res) => res.status(404).json({ error: 'Admin route not found' }));
app.use((error: unknown, _req: Request, res: Response, _next: NextFunction) => {
  const message = error instanceof Error ? error.message : 'Unknown server error';
  console.error('Unhandled API error:', message);
  if (message === 'Origin is not allowed by CORS') return res.status(403).json({ error: message });
  return res.status(500).json({ error: 'Internal server error' });
});
app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

// Vercel serves this exported Express app as a serverless function.
export = app;
