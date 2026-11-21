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
  if (code === 'PGRST202' || code === '42883') {
    return res.status(503).json({ error: 'A required database function is missing. Run the latest Supabase migration.' });
  }
  console.error('API request failed:', error);
  return res.status(500).json({ error: 'Unable to load requested data' });
};
const minor = (value: unknown) => BigInt(String(value ?? 0));
const amount = (value: bigint) => {
  const sign = value < 0n ? '-' : '';
  const abs = value < 0n ? -value : value;
  return `${sign}${abs / 100n}.${String(abs % 100n).padStart(2, '0')}`;
};
const currencyForCountry = (country?: string) => {
  const code = (country ?? '').trim().toUpperCase();
  if (code === 'RW' || code === 'RWANDA') return 'RWF';
  if (code === 'BI' || code === 'BURUNDI') return 'BIF';
  const currencies: Record<string, string> = {
    US: 'USD', CA: 'CAD', BM: 'BMD', GL: 'DKK', MX: 'MXN', BZ: 'BZD', CR: 'CRC', SV: 'USD', GT: 'GTQ', HN: 'HNL', NI: 'NIO', PA: 'PAB',
    AR: 'ARS', BO: 'BOB', BR: 'BRL', CL: 'CLP', CO: 'COP', EC: 'USD', GY: 'GYD', PY: 'PYG', PE: 'PEN', SR: 'SRD', UY: 'UYU', VE: 'VES',
    GB: 'GBP', IE: 'EUR', AT: 'EUR', BE: 'EUR', CY: 'EUR', DE: 'EUR', EE: 'EUR', ES: 'EUR', FI: 'EUR', FR: 'EUR', GR: 'EUR', HR: 'EUR',
    IT: 'EUR', LT: 'EUR', LU: 'EUR', LV: 'EUR', MC: 'EUR', ME: 'EUR', MT: 'EUR', NL: 'EUR', PT: 'EUR', SI: 'EUR', SK: 'EUR', VA: 'EUR',
    CH: 'CHF', LI: 'CHF', DK: 'DKK', FO: 'DKK', NO: 'NOK', SJ: 'NOK', SE: 'SEK', IS: 'ISK', PL: 'PLN', CZ: 'CZK', HU: 'HUF', RO: 'RON',
    BG: 'BGN', AL: 'ALL', BA: 'BAM', BY: 'BYN', MD: 'MDL', MK: 'MKD', RS: 'RSD', RU: 'RUB', UA: 'UAH', TR: 'TRY', GE: 'GEL', AM: 'AMD',
    KE: 'KES', UG: 'UGX', TZ: 'TZS', NG: 'NGN', GH: 'GHS', ZA: 'ZAR', ZM: 'ZMW', MW: 'MWK', ET: 'ETB', EG: 'EGP', MA: 'MAD',
    KM: 'KMF', DJ: 'DJF', ER: 'ERN', MG: 'MGA', MU: 'MUR', MZ: 'MZN', SC: 'SCR', SO: 'SOS', SS: 'SSP', SD: 'SDG',
    BJ: 'XOF', BF: 'XOF', CI: 'XOF', GN: 'GNF', GW: 'XOF', ML: 'XOF', NE: 'XOF', SN: 'XOF', TG: 'XOF', CV: 'CVE', GM: 'GMD', LR: 'LRD', SL: 'SLE',
    AO: 'AOA', CM: 'XAF', CF: 'XAF', TD: 'XAF', CG: 'XAF', CD: 'CDF', GQ: 'XAF', GA: 'XAF', ST: 'STN', DZ: 'DZD', LY: 'LYD', TN: 'TND',
    BW: 'BWP', LS: 'LSL', NA: 'NAD', SZ: 'SZL', ZW: 'ZWG',
    AU: 'AUD', NZ: 'NZD', FJ: 'FJD', PG: 'PGK', SB: 'SBD', VU: 'VUV', WS: 'WST', TO: 'TOP', TV: 'AUD', KI: 'AUD', NR: 'AUD',
    CN: 'CNY', HK: 'HKD', JP: 'JPY', MO: 'MOP', MN: 'MNT', KR: 'KRW', TW: 'TWD', SG: 'SGD', MY: 'MYR', ID: 'IDR', PH: 'PHP', TH: 'THB',
    VN: 'VND', KH: 'KHR', LA: 'LAK', MM: 'MMK', BN: 'BND', IN: 'INR', PK: 'PKR', BD: 'BDT', LK: 'LKR', NP: 'NPR', AF: 'AFN', MV: 'MVR',
    KZ: 'KZT', KG: 'KGS', TJ: 'TJS', TM: 'TMT', UZ: 'UZS', IL: 'ILS', JO: 'JOD', LB: 'LBP', SY: 'SYP', IQ: 'IQD', IR: 'IRR', SA: 'SAR',
    AE: 'AED', QA: 'QAR', BH: 'BHD', KW: 'KWD', OM: 'OMR', YE: 'YER', AZ: 'AZN',
    BB: 'BBD', JM: 'JMD', TT: 'TTD', DO: 'DOP', HT: 'HTG', CU: 'CUP', BS: 'BSD', AW: 'AWG', BQ: 'USD', KY: 'KYD', GD: 'XCD',
  };
  return currencies[code] ?? 'USD';
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
    const [profile, profileCountry, accounts, tx, investments, staking, commissions] = await Promise.all([
      db.from('profiles').select('full_name,country,phone,verification_status,referral_code').eq('id', res.locals.user.id).maybeSingle(),
      db.from('profiles').select('country').eq('id', res.locals.user.id).maybeSingle(),
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
    const currency = currencyForCountry(res.locals.user.country || profileCountry.data?.country);
    const availableBalance = accountRows.filter(row => row.asset_code === currency).reduce((sum, row) => sum + (balances.get(row.id) ?? 0n), 0n);
    const invested = (investments.data ?? []).filter(row => row.asset_code === currency).reduce((sum, row) => sum + minor(row.principal_minor), 0n);
    const staked = (staking.data ?? []).filter(row => row.asset_code === currency).reduce((sum, row) => sum + minor(row.principal_minor), 0n);
    const credited = (commissions.data ?? []).filter(row => row.status === 'credited').reduce((sum, row) => sum + minor(row.amount_minor), 0n);
    const pending = (commissions.data ?? []).filter(row => row.status === 'pending').reduce((sum, row) => sum + minor(row.amount_minor), 0n);
    const transactions = (tx.data ?? []).map(row => ({
      id: row.id, label: row.kind.replaceAll('_', ' ').replace(/\b\w/g, (char: string) => char.toUpperCase()),
      detail: row.description ?? row.asset_code, amount: `${row.kind === 'deposit' || row.kind === 'referral_commission' ? '+' : '−'} ${row.asset_code} ${amount(minor(row.amount_minor))}`,
      date: row.created_at, status: row.status,
    }));
    try { await db.rpc('member_sync_roi', { p_limit: 20 }); } catch {}
    const { data: roiData } = await db.rpc('member_roi_summary');
    const name = profile.data?.full_name || res.locals.user.email?.split('@')[0] || 'Member';
    return res.json({ data: {
      name, email: res.locals.user.email ?? '', currency,
      available: amount(availableBalance), invested: amount(invested), staked: amount(staked),
      referrals: amount(credited), pendingReferrals: amount(pending),
      portfolio: amount(availableBalance + invested + staked), transactions,
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
    const { data, error } = await res.locals.db.from('investment_plans').select('id,name,minimum_minor,maximum_minor,duration_days,fee_bps,roi_rate_bps,roi_interval_hours,settlement_asset_code,performance_methodology,risk_disclosure').eq('active', true).order('minimum_minor');
    if (error) throw error;
    return res.json({ data: (data ?? []).map(row => ({ ...row, minimum: amount(minor(row.minimum_minor)), maximum: row.maximum_minor == null ? null : amount(minor(row.maximum_minor)) })) });
  } catch (error) { return fail(res, error); }
});

app.get('/api/member/returns', async (_req, res: SessionResponse) => {
  try {
    const { data, error } = await res.locals.db.rpc('member_roi_summary');
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

app.get('/api/admin/users', async (req, res: SessionResponse) => {
  try {
    const search = String(req.query.search ?? '').slice(0, 120);
    const status = String(req.query.status ?? 'All users').slice(0, 40);
    const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 200);
    const offset = Math.max(Number(req.query.offset) || 0, 0);
    const { data, error } = await res.locals.db.rpc('admin_list_users', { p_search: search, p_status: status, p_limit: limit, p_offset: offset });
    if (error) return fail(res, error);
    return res.json({ data });
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
    const { data, error } = await res.locals.db.rpc('admin_update_user', {
      p_id: req.params.id,
      p_full_name: String(req.body?.full_name ?? ''),
      p_country: String(req.body?.country ?? ''),
      p_phone: String(req.body?.phone ?? ''),
      p_status: String(req.body?.status ?? 'active'),
    });
    if (error) return fail(res, error);
    return res.json({ data });
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
    const { data, error } = await res.locals.db.from('investments')
      .select('id,principal_minor,asset_code,status,created_at,owner_id,investment_plans(name)')
      .order('created_at', { ascending: false }).limit(200);
    if (error) return fail(res, error);
    const rows = data ?? [];
    const ids = Array.from(new Set(rows.map(row => row.owner_id)));
    const profiles = ids.length ? await res.locals.db.from('profiles').select('id,full_name').in('id', ids) : { data: [], error: null };
    if (profiles.error) return fail(res, profiles.error);
    const names = new Map((profiles.data ?? []).map(row => [row.id, row.full_name]));
    return res.json({ data: rows.map(row => ({
      id: row.id,
      user: names.get(row.owner_id) ?? String(row.owner_id).slice(0, 8),
      plan: (row as any).investment_plans?.name ?? 'Plan',
      amount: amount(minor(row.principal_minor)), principal_minor: row.principal_minor,
      asset_code: row.asset_code,
      status: row.status,
      date: row.created_at,
    })) });
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
