import {createClient} from '@supabase/supabase-js';
import {PROJECT_SUPABASE_PUBLISHABLE_KEY,PROJECT_SUPABASE_URL} from '../src/supabaseConfig';

const url=process.env.SUPABASE_URL||PROJECT_SUPABASE_URL;
const key=process.env.SUPABASE_PUBLISHABLE_KEY||PROJECT_SUPABASE_PUBLISHABLE_KEY;
const authClient=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
const minor=(value:unknown)=>BigInt(String(value??0));
const amount=(value:bigint)=>`${value<0n?'-':''}${(value<0n?-value:value)/100n}.${String((value<0n?-value:value)%100n).padStart(2,'0')}`;
const fail=(res:any,error:unknown)=>{console.error('API request failed:',error);return res.status(500).json({error:'Unable to load requested data'});};

export default async function handler(req:any,res:any){
  if(req.method!=='GET')return res.status(405).json({error:'Method not allowed'});
  const pathname=new URL(req.url||'/',`https://${req.headers.host||'localhost'}`).pathname;
  const route=pathname.replace(/^\/api\/?/,'').replace(/\/$/,'');
  if(route==='health')return res.status(200).json({status:'ok',database:'configured',mode:'test'});
  const authorization=String(req.headers.authorization||'');
  const token=authorization.startsWith('Bearer ')?authorization.slice(7):'';
  if(!token)return res.status(401).json({error:'Authentication required'});
  try{
    const {data:authData,error:authError}=await authClient.auth.getUser(token);
    if(authError||!authData.user)return res.status(401).json({error:'Invalid session'});
    const user=authData.user;
    const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:`Bearer ${token}`}}});
    const {data:member,error:memberError}=await db.from('profiles').select('status').eq('id',user.id).maybeSingle();
    if(memberError)return fail(res,memberError);
    if(member?.status==='suspended')return res.status(403).json({error:'Account is suspended'});

    if(route==='member/dashboard'){
      const [profile,accounts,tx,investments,commissions]=await Promise.all([
        db.from('profiles').select('full_name,country,phone,verification_status,referral_code').eq('id',user.id).maybeSingle(),
        db.from('asset_accounts').select('id,asset_code').eq('owner_id',user.id),
        db.from('ledger_transactions').select('id,kind,status,amount_minor,asset_code,description,created_at').eq('owner_id',user.id).order('created_at',{ascending:false}).limit(5),
        db.from('investments').select('principal_minor,asset_code,status').eq('owner_id',user.id).in('status',['active','pending']),
        db.from('referral_commissions').select('amount_minor,status').eq('referrer_id',user.id),
      ]);
      for(const result of [profile,accounts,tx,investments,commissions])if(result.error)throw result.error;
      const accountRows=accounts.data??[];const ids=accountRows.map((r:any)=>r.id);
      const entries=ids.length?await db.from('ledger_entries').select('account_id,amount_minor').in('account_id',ids):{data:[],error:null};
      if(entries.error)throw entries.error;
      const balances=new Map<string,bigint>();for(const row of entries.data??[])balances.set(row.account_id,(balances.get(row.account_id)??0n)+minor(row.amount_minor));
      const available=accountRows.filter((r:any)=>r.asset_code==='USD').reduce((s:number,r:any)=>s+Number(balances.get(r.id)??0n),0);
      const invested=(investments.data??[]).filter((r:any)=>r.asset_code==='USD').reduce((s:bigint,r:any)=>s+minor(r.principal_minor),0n);
      const credited=(commissions.data??[]).filter((r:any)=>r.status==='credited').reduce((s:bigint,r:any)=>s+minor(r.amount_minor),0n);
      const pending=(commissions.data??[]).filter((r:any)=>r.status==='pending').reduce((s:bigint,r:any)=>s+minor(r.amount_minor),0n);
      const transactions=(tx.data??[]).map((r:any)=>({id:r.id,label:r.kind.replaceAll('_',' ').replace(/\b\w/g,(c:string)=>c.toUpperCase()),detail:r.description??r.asset_code,amount:`${r.kind==='deposit'||r.kind==='referral_commission'?'+':'−'} ${r.asset_code} ${amount(minor(r.amount_minor))}`,date:r.created_at,status:r.status}));
      return res.json({data:{name:profile.data?.full_name||user.email?.split('@')[0]||'Member',email:user.email??'',currency:'USD',available:amount(BigInt(available)),invested:amount(invested),bonus:amount(0n),referrals:amount(credited),pendingReferrals:amount(pending),portfolio:amount(BigInt(available)+invested),transactions,profile:profile.data??null,verifiedPerformance:false}});
    }
    if(route==='member/transactions'){
      const limit=Math.min(Math.max(Number(req.query?.limit)||25,1),100);
      const {data,error}=await db.from('ledger_transactions').select('id,kind,status,amount_minor,asset_code,provider_reference,description,created_at,completed_at').eq('owner_id',user.id).order('created_at',{ascending:false}).limit(limit);
      if(error)throw error;return res.json({data:(data??[]).map((r:any)=>({...r,amount:amount(minor(r.amount_minor))}))});
    }
    if(route==='member/wallet'){
      const {data:accounts,error}=await db.from('asset_accounts').select('id,asset_code').eq('owner_id',user.id);if(error)throw error;
      const rows=accounts??[];const entries=rows.length?await db.from('ledger_entries').select('account_id,amount_minor').in('account_id',rows.map((r:any)=>r.id)):{data:[],error:null};if(entries.error)throw entries.error;
      const sums=new Map<string,bigint>();for(const e of entries.data??[])sums.set(e.account_id,(sums.get(e.account_id)??0n)+minor(e.amount_minor));
      return res.json({data:rows.map((r:any)=>({asset:r.asset_code,balance:amount(sums.get(r.id)??0n)}))});
    }
    if(route==='member/investments'){
      const {data,error}=await db.from('investments').select('id,principal_minor,asset_code,status,created_at,investment_plans(name,duration_days,fee_bps,risk_disclosure,performance_methodology)').eq('owner_id',user.id).order('created_at',{ascending:false});
      if(error)throw error;return res.json({data:(data??[]).map((r:any)=>({...r,principal:amount(minor(r.principal_minor))}))});
    }
    if(route==='member/referrals'){
      const [profile,commissions,summary]=await Promise.all([
        db.from('profiles').select('referral_code').eq('id',user.id).maybeSingle(),
        db.from('referral_commissions').select('id,invitee_id,amount_minor,status,created_at,credited_at').eq('referrer_id',user.id).order('created_at',{ascending:false}),
        db.rpc('member_referral_summary'),
      ]);
      for(const result of [profile,commissions,summary])if(result.error)throw result.error;
      return res.json({data:{referralCode:profile.data?.referral_code??null,summary:summary.data,commissions:(commissions.data??[]).map((r:any)=>({...r,amount:amount(minor(r.amount_minor))}))}});
    }
    if(route==='member/profile'){
      const {data,error}=await db.from('profiles').select('id,full_name,country,phone,verification_status,referral_code,created_at').eq('id',user.id).maybeSingle();
      if(error)throw error;return res.json({data:{...data,email:user.email}});
    }
    if(route==='investment-plans'){
      const {data,error}=await db.from('investment_plans').select('id,name,minimum_minor,maximum_minor,duration_days,fee_bps,roi_rate_bps,roi_interval_hours,settlement_asset_code,performance_methodology,risk_disclosure').eq('active',true).eq('settlement_asset_code','USD').order('minimum_minor');
      if(error)throw error;return res.json({data:(data??[]).map((r:any)=>({...r,minimum:amount(minor(r.minimum_minor)),maximum:r.maximum_minor==null?null:amount(minor(r.maximum_minor))}))});
    }
    if(route.startsWith('admin/'))return res.status(503).json({error:'Admin management service is not configured'});
    return res.status(404).json({error:'Not found'});
  }catch(error){return fail(res,error);}
}
