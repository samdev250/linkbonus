import {useEffect,useState} from 'react';
import {ArrowRight, Bell, Building2, CheckCircle2, Copy, Gift, Globe2, Image as ImageIcon, Loader2, Mail, MessageCircle, Pencil, Plus, ReceiptText, Send, ShieldCheck, TrendingUp, Upload, Wallet, X, XCircle} from 'lucide-react';
import countryToCurrency from 'country-to-currency';
import {apiUrl,supabase} from './supabase';
import {countryCodes,countryRegions} from './countries';
import {isBurundi} from './directBonus';

const client = async (token:string,path:string,init:RequestInit={}) => {
  const response = await fetch(`${apiUrl}${path}`,{...init,headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`,...(init.headers||{})}});
  const body = await response.json().catch(()=>({}));
  if(!response.ok) throw new Error(body.error||'Request failed');
  return body.data;
};
const minorMoney = (value:any,money:(v:string)=>string,asset?:string) => asset?`${asset} ${new Intl.NumberFormat(undefined,{minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(value||0)/100)}`:money(String((Number(value||0)/100).toFixed(2)));
const dateLabel = (value:any) => value?new Date(value).toLocaleString():'Not scheduled';
const withBreaks = (value:any) => String(value||'').replace(/<br\s*\/?>/gi,'\n').split(/\r?\n/).map((line:string,i:number)=><span key={i}>{i>0&&<br/>}{line}</span>);
const DAILY_RATE_BPS = 500;
const SUPPORT_WHATSAPP_NUMBER = '+250793658206';
const planAssetOptions=[...new Set([...Object.values(countryToCurrency),'BTC','ETH','USDT','USDC'])].sort();

export function InvestPage({data,money,token,onChoose,onDirectBonus}:any){
  const burundi=isBurundi(data?.profile?.country,data?.currency);
  const [tab,setTab]=useState('Available Plans');
  const [plans,setPlans]=useState<any[]>([]);
  const [rows,setRows]=useState<any[]>([]);
  const [proofs,setProofs]=useState<any[]>([]);
  const [loading,setLoading]=useState(false);
  const [errors,setErrors]=useState<Record<string,string>>({});
  const load=async()=>{
    setLoading(true);
    const results=await Promise.allSettled([
      client(token,'/investment-plans'),
      client(token,'/member/investments'),
      client(token,'/member/payment-proofs'),
    ]);
    const nextErrors:Record<string,string>={};
    const message=(reason:unknown)=>reason instanceof Error?reason.message:'Request failed';
    const [planResult,investmentResult,proofsResult]=results;
    if(planResult.status==='fulfilled')setPlans(planResult.value as any[]);else nextErrors.plans=message(planResult.reason);
    if(investmentResult.status==='fulfilled')setRows(investmentResult.value as any[]);else nextErrors.investments=message(investmentResult.reason);
    if(proofsResult.status==='fulfilled')setProofs(proofsResult.value as any[]);else nextErrors.proofs=message(proofsResult.reason);
    setErrors(nextErrors);
    setLoading(false);
  };
  useEffect(()=>{load()},[token]);
  const errorLabels:Record<string,string>={plans:'Investment plans',investments:'Your investments',proofs:'Payment proofs'};
  return <>
    {burundi&&<div className="section-heading"><div><h2>Received Bonus</h2><p>Review the LINK BONUS details for Burundi members.</p></div><button className="outline-button" onClick={onDirectBonus}><Gift size={16}/> View Direct Bonus</button></div>}
    {Object.entries(errors).map(([key,message])=><div className="notice-banner data-error" key={key}><ShieldCheck size={18}/><span><b>{errorLabels[key]||'Investment data'} unavailable</b><small>{message}</small></span></div>)}
    <div className="tabs"> {['Available Plans','My Investments'].map(x=><button className={tab===x?'selected':''} onClick={()=>setTab(x)} key={x}>{x}</button>)}</div>
    {loading&&<div className="inline-loading"><Loader2 size={15} className="spin"/> Loading investment data…</div>}
    {tab==='Available Plans'?<>
      <div className="notice-banner"><ShieldCheck size={19}/><span><b>Investment plans</b><small>Each plan shows its own daily income rate and credit cycle. Your plan activates automatically once your payment proof is verified.</small></span><span className="status-tag">PLAN RATES</span></div>
      <div className="plan-grid">{plans.map((p,i)=>{const rate=Number(p.roi_rate_bps||DAILY_RATE_BPS);return <article className="plan-card" key={p.id}><div className="plan-top"><span className={`plan-symbol ps${i%4}`}><TrendingUp size={18}/></span><span className="status-tag">{p.duration_days?`${p.duration_days} DAYS`:'FLEXIBLE'}</span></div><h3>{p.name}</h3><div className="plan-details"><span>Daily income <b>{rate/100}% · {minorMoney(Number(p.minimum_minor)*rate/10000,money,p.settlement_asset_code)}</b></span><span>Credit cycle <b>Every {p.roi_interval_hours||24}h</b></span><span>Starts <b>After verification</b></span><span>Duration <b>{p.duration_days?`${p.duration_days} days`:'Flexible'}</b></span></div><button className="plan-button" onClick={()=>onChoose({...p,amount:Number(p.minimum_minor)/100})}>Choose plan <ArrowRight size={15}/></button></article>})}</div>
      {!loading&&!errors.plans&&!plans.length&&<section className="panel empty-state"><span><TrendingUp/></span><h2>No plans are open yet</h2><p>Administration will publish the available plans shortly.</p></section>}
    </>:<>
      <section className="panel table-panel"><div className="panel-heading"><div><h2>My investments</h2><p>Active positions and their calculated returns.</p></div></div><div className="workflow-table"><div className="workflow-head"><span>Plan</span><span>Principal</span><span>Daily return</span><span>Credited</span><span>Next credit</span><span>Status</span></div>{rows.map(r=><div className="workflow-row" key={r.id}><b>{r.plan}{r.creation_source==='admin'&&<small>Admin-created</small>}{r.admin_funding_method==='no_wallet_debit'&&<small>No wallet debit</small>}</b><span>{minorMoney(r.principal_minor,money,r.asset_code)}</span><span>{minorMoney(Number(r.principal_minor)*Number(r.rate_bps)/10000,money,r.asset_code)}</span><span>{minorMoney(r.paid_minor,money,r.asset_code)}</span><span>{dateLabel(r.next_roi_at)}</span><span className={`status-tag ${r.status==='active'?'':'muted'}`}>{r.status}</span></div>)}{!rows.length&&!loading&&!errors.investments&&<div className="admin-empty-row">No investments yet.</div>}</div></section>
      <section className="panel table-panel"><div className="panel-heading"><div><h2>Payment proof submissions</h2><p>Track the deposits you sent for review.</p></div></div><div className="workflow-table"><div className="workflow-head"><span>Reference</span><span>Amount</span><span>Submitted</span><span>Status</span><span>Note</span></div>{proofs.map(p=><div className="workflow-row" key={p.id}><b>{p.provider_reference||p.id.slice(0,8)}</b><span>{minorMoney(p.amount_minor,money,p.asset_code)}</span><span>{dateLabel(p.created_at)}</span><span className={`status-tag ${p.status==='approved'?'':'muted'}`}>{p.status}</span><span>{p.rejection_reason||'—'}</span></div>)}{!proofs.length&&!loading&&!errors.proofs&&<div className="admin-empty-row">No proof submissions yet.</div>}</div></section>
    </>}
  </>;
}

export function InvitationsView({token,toast}:any){
  const [email,setEmail]=useState('');
  const [rows,setRows]=useState<any[]>([]);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState('');
  const load=()=>client(token,'/member/invitations').then(d=>setRows(d as any[])).catch(e=>setError(e.message));
  useEffect(()=>{load()},[token]);
  const create=async(e:React.FormEvent)=>{e.preventDefault();setBusy(true);setError('');try{await client(token,'/member/invitations',{method:'POST',body:JSON.stringify({email})});setEmail('');load();toast('Invitation link created')}catch(err){setError(err instanceof Error?err.message:'Could not create invitation')}finally{setBusy(false)}};
  const copy=(row:any)=>{const link=`${window.location.origin}/?invite=${row.token}`;navigator.clipboard?.writeText(link).then(()=>toast('Invitation link copied')).catch(()=>toast(link))};
  return <section className="panel invite-panel workflow-invite"><div><h2>Invite someone</h2><p>Create a private invitation link for a friend.</p></div><form className="invite-form" onSubmit={create}><input required type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="friend@example.com"/><button className="primary compact" disabled={busy} type="submit"><Mail size={15}/> Create invite</button></form>{error&&<div className="form-error">{error}</div>}<div className="invite-list">{rows.map(r=><div className="invite-row" key={r.id}><span className="invite-mail"><Mail size={15}/>{r.email}</span><span className={`status-tag ${r.status==='accepted'?'':'muted'}`}>{r.status}</span><span>{dateLabel(r.created_at)}</span><button className="text-button" onClick={()=>copy(r)}><Copy size={14}/> Copy link</button></div>)}{!rows.length&&<div className="admin-empty-row">No invitations created yet.</div>}</div></section>;
}

export function ProofForm({token,data,amount,plan,onDone,onCancel,money,amountInput}:any){
  const [phone,setPhone]=useState(data?.profile?.phone||'');
  const [payerName,setPayerName]=useState(data?.name||'');
  const [file,setFile]=useState<File|null>(null);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState('');
  const submit=async(e:React.FormEvent)=>{e.preventDefault();setError('');const numericAmount=Number(amount);if(!Number.isFinite(numericAmount)||numericAmount<=0){setError('Enter an amount greater than zero');return}if(!file){setError('Attach a payment screenshot');return}if(!supabase){setError('Upload service is unavailable');return}setBusy(true);try{const {data:auth}=await supabase.auth.getUser();const user=auth.user;if(!user)throw new Error('Sign in again to upload');const path=`${user.id}/${Date.now()}-${file.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;const upload=await supabase.storage.from('payment-proofs').upload(path,file,{contentType:file.type,upsert:false});if(upload.error)throw upload.error;await client(token,'/member/payment-proofs',{method:'POST',body:JSON.stringify({amount_minor:Math.round(numericAmount*100),asset_code:data?.currency||'RWF',screenshot_path:path,phone,full_name:payerName,payer_name:payerName,plan_id:plan?.id||null})});onDone()}catch(err){setError(err instanceof Error?err.message:'Could not submit proof')}finally{setBusy(false)}};
  return <form className="proof-form" onSubmit={submit}>{amountInput}<PaymentInstructions token={token} country={data?.profile?.country} compact/><div className="proof-summary"><ReceiptText size={20}/><div><b>{plan?`${plan.name} plan`:'Deposit'}</b><small>{money(String(amount||0))} · Your plan activates automatically after verification</small></div></div><div className="proof-fields"><label><span>Name used to pay</span><input required value={payerName} onChange={e=>setPayerName(e.target.value)} placeholder="Name shown on the payment"/></label><label><span>Number used to pay</span><input required value={phone} onChange={e=>setPhone(e.target.value)} placeholder="Phone or payment number"/></label><label><span>Payment screenshot</span><input required type="file" accept="image/*" onChange={e=>setFile(e.target.files?.[0]||null)}/></label></div>{file&&<div className="proof-preview"><ImageIcon size={15}/> {file.name}</div>}{error&&<div className="form-error">{error}</div>}<div className="proof-actions"><button className="primary compact" disabled={busy} type="submit"><Upload size={15}/> {busy?'Submitting…':'Submit proof'}</button><button className="outline-button" type="button" onClick={onCancel}>Cancel</button></div></form>;
}

export function AdminProofsView({token,toast}:any){
  const [status,setStatus]=useState('pending');
  const [rows,setRows]=useState<any[]>([]);
  const [links,setLinks]=useState<Record<string,string>>({});
  const [previewUrl,setPreviewUrl]=useState('');
  const [loading,setLoading]=useState(false);
  const [busy,setBusy]=useState('');
  useEffect(()=>{if(!previewUrl)return;const closeOnEscape=(event:KeyboardEvent)=>{if(event.key==='Escape')setPreviewUrl('')};window.addEventListener('keydown',closeOnEscape);return()=>window.removeEventListener('keydown',closeOnEscape)},[previewUrl]);
  const load=async()=>{setLoading(true);try{const d=await client(token,`/admin/payment-proofs?status=${encodeURIComponent(status)}`);const list=(d as any).rows||[];setRows(list as any[]);const storage=supabase?.storage;if(storage){const pairs=await Promise.all(list.map(async(r:any)=>{const {data}=await storage.from('payment-proofs').createSignedUrl(r.screenshot_path,3600);return [r.id,data?.signedUrl||''] as const}));setLinks(Object.fromEntries(pairs))}}catch{}finally{setLoading(false)}};
  useEffect(()=>{load()},[token,status]);
  const review=async(id:string,action:string)=>{const note=action==='approve'?'':window.prompt(action==='reject'?'Reason for rejection':'Reason for cancellation')||'';if(action!=='approve'&&!note)return;setBusy(id);try{await client(token,`/admin/payment-proofs/${id}/review`,{method:'POST',body:JSON.stringify({action,note})});toast(action==='approve'?'Proof approved · plan activated and counting':`Proof ${action==='reject'?'rejected':'cancelled'}`);load()}catch(e){toast(e instanceof Error?e.message:'Review failed')}finally{setBusy('')}};
  return <section className="panel table-panel"><div className="table-toolbar"><div><h2>Payment proofs</h2><p>Review deposit evidence submitted by members.</p></div><button className="outline-button" onClick={load}>Refresh</button></div><div className="tabs admin-tabs">{['pending','approved','rejected','cancelled','all'].map(x=><button className={status===x?'selected':''} onClick={()=>setStatus(x)} key={x}>{x}</button>)}</div><div className="workflow-table"><div className="workflow-head"><span>Member</span><span>Amount</span><span>Details</span><span>Proof</span><span>Status</span><span>Review</span></div>{rows.map(r=><div className="workflow-row" key={r.id}><div className="user-cell"><span className="avatar small">{String(r.name||'U').slice(0,1).toUpperCase()}</span><div><b>{r.name}</b><small>{r.email}</small></div></div><b>{r.asset_code} {String(Number(r.amount_minor||0)/100)}</b><span>{r.payer_name||'—'}<small>{r.phone||'—'}</small></span><span>{links[r.id]?<button type="button" className="text-button" aria-haspopup="dialog" onClick={()=>setPreviewUrl(links[r.id])}>View screenshot</button>:'Screenshot'}</span><span className={`status-tag ${r.status==='approved'?'':'muted'}`}>{r.status}</span><span className="proof-actions">{r.status==='pending'?<><button className="text-button" disabled={!!busy} onClick={()=>review(r.id,'approve')}><CheckCircle2 size={14}/> Approve</button><button className="text-button" disabled={!!busy} onClick={()=>review(r.id,'reject')}><XCircle size={14}/> Reject</button><button className="text-button muted-link" disabled={!!busy} onClick={()=>review(r.id,'cancel')}>Cancel</button></>:<span className="muted-link">{r.rejection_reason||'Reviewed'}</span>}</span></div>)}{!rows.length&&!loading&&<div className="admin-empty-row">No {status==='all'?'':status} payment proofs.</div>}</div>{previewUrl&&<div className="modal-backdrop proof-preview-backdrop" onClick={()=>setPreviewUrl('')}><div className="modal proof-preview-modal" role="dialog" aria-modal="true" aria-labelledby="proof-preview-title" onClick={e=>e.stopPropagation()}><div className="modal-head"><div><span className="eyebrow">PAYMENT PROOF</span><h2 id="proof-preview-title">Screenshot</h2></div><button type="button" className="icon-button" autoFocus aria-label="Close screenshot preview" onClick={()=>setPreviewUrl('')}><X size={19}/></button></div><img className="proof-preview-image" src={previewUrl} alt="Submitted payment screenshot"/></div></div>}</section>;
}

const countryNames = (()=>{try{return new Intl.DisplayNames(['en'],{type:'region'})}catch{return null}})();
const countryLabel = (code:string)=>code?countryNames?.of(code.toUpperCase())||code.toUpperCase():'your country';
const countryOptions = ['RW','CD','BI','ZM','ZA','KE','TZ','UG','DE','US','GB','FR','CA','NG','GH','SN','CI','CM','MA','EG','IN','AE','SA','CN','JP','AU'];
const allCountryCodes = Array.from(new Set(Object.values(countryRegions).flat())).sort((a,b)=>countryLabel(a).localeCompare(countryLabel(b)));

export function NotificationBell({token,toast}:any){
  const [rows,setRows]=useState<any[]>([]);
  const [open,setOpen]=useState(false);
  const load=()=>client(token,'/member/notifications').then(d=>setRows(d as any[])).catch(()=>{});
  useEffect(()=>{load();const timer=setInterval(load,60000);return()=>clearInterval(timer)},[token]);
  const unread=rows.filter(r=>!r.read).length;
  const mark=async(id:string)=>{try{await client(token,`/member/notifications/${id}/read`,{method:'POST'});setRows(current=>current.map(r=>r.id===id?{...r,read:true}:r))}catch(e){toast(e instanceof Error?e.message:'Could not mark notification')}};
  return <div className="notification-wrap"><button className="icon-button bell-button" aria-label="Notifications" aria-expanded={open} onClick={()=>setOpen(!open)}><Bell size={18}/>{unread>0&&<span className="bell-badge">{unread}</span>}</button>{open&&<><button className="notification-backdrop" aria-label="Close notifications" onClick={()=>setOpen(false)}/><div className="notification-menu"><div className="notification-head"><b>Notifications</b><small>{unread} unread</small></div><div className="notification-list">{rows.map(r=><button className={`notification-item ${r.read?'':'unread'}`} key={r.id} onClick={()=>mark(r.id)}><span><b>{r.title}</b><small>{dateLabel(r.created_at)}</small></span><p>{r.body}</p>{!r.read&&<em>Mark as read</em>}</button>)}{!rows.length&&<div className="admin-empty-row">No notifications yet.</div>}</div></div></>}</div>;
}

export function PaymentInstructions({token,country,compact}:any){
  const [row,setRow]=useState<any>(null);
  useEffect(()=>{setRow(null);client(token,`/payment-instructions?country=${encodeURIComponent(String(country||''))}`).then(setRow).catch(()=>setRow({configured:false}))},[token,country]);
  if(!row)return <div className="inline-loading"><Loader2 size={15} className="spin"/> Loading payment details…</div>;
  if(!row.configured)return <div className="notice-banner"><ShieldCheck size={18}/><span><b>Payment instructions pending</b><small>Administration has not published deposit details for {countryLabel(String(country||''))} yet. Contact support for help.</small></span></div>;
  return <section className={`panel payment-instructions ${compact?'compact':''}`}><div className="panel-heading"><div><h2>Pay for {countryLabel(row.country_code)}</h2><p>{compact?'Follow these details before submitting your screenshot.':'Use these details for deposits, then submit your proof below.'}</p></div><span className="status-tag">VERIFIED PAYEE</span></div><div className="payment-detail-grid"><div><small>Account name</small><b>{row.account_name}</b></div><div><small>Account number</small><b>{row.account_number}</b></div><div><small>Bank / provider</small><b>{row.bank_name||'Not specified'}</b></div></div>{row.instructions&&<p className="payment-note">{withBreaks(row.instructions)}</p>}</section>;
}

export function SupportCard({token}:any){
  const [settings,setSettings]=useState<any>(null);
  useEffect(()=>{client(token,'/support-settings').then(setSettings).catch(()=>setSettings({support_email:'infolinkbonusinvest@gmail.com'}))},[token]);
  const email=settings?.support_email||'infolinkbonusinvest@gmail.com';
  return <section className="panel support-panel"><div className="support-panel-head"><span><MessageCircle size={20}/></span><div><h2>Help & support</h2><p>Reach the team or join the community group.</p></div></div><div className="support-actions"><a className="support-action" href={`mailto:${email}?subject=LINK%20BONUS%20support`}><Mail size={17}/><span><b>Contact us via email</b><small>{email}</small></span></a><div className="support-action info"><MessageCircle size={17}/><span><b>WhatsApp us</b><small>{SUPPORT_WHATSAPP_NUMBER}</small></span></div>{settings?.telegram_url?<a className="support-action" href={settings.telegram_url} target="_blank" rel="noreferrer"><Send size={17}/><span><b>Join Telegram group</b><small>Open the member announcements channel</small></span></a>:<button className="support-action disabled" disabled><Send size={17}/><span><b>Join Telegram group</b><small>Link not set by administration</small></span></button>}</div></section>;
}

export function AdminNotificationsView({token,toast}:any){
  const [rows,setRows]=useState<any[]>([]);
  const [title,setTitle]=useState('');
  const [body,setBody]=useState('');
  const [audience,setAudience]=useState('all');
  const [country,setCountry]=useState('RW');
  const [email,setEmail]=useState('');
  const [busy,setBusy]=useState(false);
  const load=()=>client(token,'/admin/notifications').then(d=>setRows(d as any[])).catch(()=>{});
  useEffect(()=>{load()},[token]);
  const send=async(e:React.FormEvent)=>{e.preventDefault();setBusy(true);try{await client(token,'/admin/notifications',{method:'POST',body:JSON.stringify({title,body,audience,country_code:audience==='country'?country:null,user_email:audience==='user'?email:null})});setTitle('');setBody('');setEmail('');toast('Notification sent');load()}catch(err){toast(err instanceof Error?err.message:'Could not send notification')}finally{setBusy(false)}};
  return <><section className="panel compose-panel"><div className="panel-heading"><div><h2>Send notification</h2><p>Broadcast to everyone, one country, or a single member.</p></div><Bell size={19}/></div><form className="compose-form" onSubmit={send}><label><span>Audience</span><select value={audience} onChange={e=>setAudience(e.target.value)}><option value="all">All members</option><option value="country">One country</option><option value="user">One member by email</option></select></label>{audience==='country'&&<label><span>Country</span><input required value={country} onChange={e=>setCountry(e.target.value)} list="notification-countries" maxLength={2}/></label>}{audience==='user'&&<label><span>Member email</span><input required type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="member@example.com"/></label>}<label className="compose-title"><span>Title</span><input required value={title} onChange={e=>setTitle(e.target.value)} placeholder="Short headline"/></label><label className="compose-body"><span>Message</span><textarea required value={body} onChange={e=>setBody(e.target.value)} placeholder="What should members know?"/></label><button className="primary compact" disabled={busy} type="submit"><Send size={15}/> {busy?'Sending…':'Send notification'}</button></form><datalist id="notification-countries">{countryOptions.map(c=><option value={c} key={c}>{countryLabel(c)}</option>)}</datalist></section><section className="panel table-panel"><div className="panel-heading"><div><h2>Notification history</h2><p>Messages sent from the administration workspace.</p></div><button className="outline-button" onClick={load}>Refresh</button></div><div className="workflow-table"><div className="workflow-head notification-head-grid"><span>Title</span><span>Audience</span><span>Sender</span><span>Reads</span><span>Sent</span><span/></div>{rows.map(r=><div className="workflow-row notification-head-grid" key={r.id}><b>{r.title}</b><span>{r.audience==='all'?'Everyone':r.audience==='country'?countryLabel(r.country_code):'Single member'}</span><span>{r.sender}</span><span>{r.reads}</span><span>{dateLabel(r.created_at)}</span><span className="muted-link">{r.audience}</span></div>)}{!rows.length&&<div className="admin-empty-row">No notifications sent yet.</div>}</div></section></>;
}

export function AdminPlansView({token,toast}:any){
  const blank=()=>({id:null,name:'',minimum:'',maximum:'',duration_days:'',fee_percent:'0',roi_percent:'5',roi_interval_hours:24,settlement_asset_code:'USD',country_code:'',performance_methodology:'',risk_disclosure:'',active:true});
  const [rows,setRows]=useState<any[]>([]);
  const [form,setForm]=useState<any>(blank());
  const [busy,setBusy]=useState(false);
  const load=async()=>{try{setRows(await client(token,'/admin/plans') as any[])}catch(e){toast(e instanceof Error?e.message:'Could not load plans')}};
  useEffect(()=>{load()},[token]);
  const fmt=(v:any,asset?:string)=>`${asset?`${asset} `:''}${new Intl.NumberFormat(undefined,{minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(v||0)/100)}`;
  const edit=(p:any)=>setForm({...blank(),id:p.id,name:p.name,minimum:String(Number(p.minimum_minor||0)/100),maximum:p.maximum_minor?String(Number(p.maximum_minor)/100):'',duration_days:p.duration_days??'',fee_percent:String(Number(p.fee_bps||0)/100),roi_percent:String(Number(p.roi_rate_bps||500)/100),roi_interval_hours:p.roi_interval_hours||24,settlement_asset_code:p.settlement_asset_code||'USD',country_code:p.country_code||'',performance_methodology:p.performance_methodology||'',risk_disclosure:p.risk_disclosure||'',active:p.active!==false});
  const save=async(e:React.FormEvent)=>{e.preventDefault();setBusy(true);try{await client(token,'/admin/plans',{method:'POST',body:JSON.stringify(form)});setForm(blank());toast(form.id?'Plan updated':'Plan added');load()}catch(err){toast(err instanceof Error?err.message:'Could not save plan')}finally{setBusy(false)}};
  return <><section className="panel settings-panel"><div className="panel-heading"><div><h2>Investment plans</h2><p>Edit plan values, income rates and visibility from one place.</p></div><TrendingUp size={19}/></div><div className="workflow-table"><div className="workflow-head settings-head-grid"><span>Plan</span><span>Minimum</span><span>Daily income</span><span>Cycle</span><span>Status</span><span/></div>{rows.map(r=><div className="workflow-row settings-head-grid" key={r.id}><b>{r.name}<small>{r.duration_days?`${r.duration_days} days`:'Flexible'} · {r.settlement_asset_code||'USD'} · {r.country_code?countryLabel(r.country_code):'All countries'}</small></b><span>{fmt(r.minimum_minor,r.settlement_asset_code)}</span><span>{Number(r.roi_rate_bps||500)/100}% · {fmt(Number(r.minimum_minor||0)*Number(r.roi_rate_bps||500)/10000,r.settlement_asset_code)}</span><span>Every {r.roi_interval_hours||24}h</span><span className={`status-tag ${r.active?'':'muted'}`}>{r.active?'Visible':'Hidden'}</span><span className="proof-actions"><button className="text-button" onClick={()=>edit(r)}><Pencil size={13}/> Edit</button></span></div>)}{!rows.length&&<div className="admin-empty-row">No plans configured yet.</div>}</div></section><section className="panel settings-panel"><div className="panel-heading"><div><h2>{form.id?'Edit plan':'Add a new plan'}</h2><p>Changes appear on the member investment page immediately after saving.</p></div><Plus size={19}/></div><form className="settings-form plan-admin-form" onSubmit={save}><div className="settings-form-title"><b>{form.id?`Editing ${form.name}`:'Plan configuration'}</b><small>Amounts use plan currency; income rates are percentages of active principal.</small></div><label><span>Plan name</span><input required value={form.name} onChange={e=>setForm({...form,name:e.target.value})} placeholder="e.g. Starter"/></label><label><span>Country</span><select value={form.country_code} onChange={e=>setForm({...form,country_code:e.target.value})}><option value="">All countries</option>{allCountryCodes.map(c=><option value={c} key={c}>{countryLabel(c)} ({c})</option>)}</select></label><label><span>Minimum amount</span><input required type="number" min="0.01" step="0.01" value={form.minimum} onChange={e=>setForm({...form,minimum:e.target.value})}/></label><label><span>Maximum amount</span><input type="number" min="0" step="0.01" value={form.maximum} onChange={e=>setForm({...form,maximum:e.target.value})} placeholder="Blank for no limit"/></label><label><span>Duration days</span><input type="number" min="1" step="1" value={form.duration_days} onChange={e=>setForm({...form,duration_days:e.target.value})} placeholder="Blank for flexible"/></label><label><span>Fee %</span><input type="number" min="0" max="100" step="0.01" value={form.fee_percent} onChange={e=>setForm({...form,fee_percent:e.target.value})}/></label><label><span>Daily income %</span><input required type="number" min="0" max="1000" step="0.01" value={form.roi_percent} onChange={e=>setForm({...form,roi_percent:e.target.value})}/></label><label><span>Credit interval (hours)</span><input required type="number" min="1" max="8760" step="1" value={form.roi_interval_hours} onChange={e=>setForm({...form,roi_interval_hours:e.target.value})}/></label><label><span>Settlement asset</span><select value={form.settlement_asset_code} onChange={e=>setForm({...form,settlement_asset_code:e.target.value})}>{planAssetOptions.map(c=><option key={c} value={c}>{c}</option>)}</select></label><label className="settings-wide"><span>Performance methodology</span><textarea value={form.performance_methodology} onChange={e=>setForm({...form,performance_methodology:e.target.value})} placeholder="How income is calculated"/></label><label className="settings-wide"><span>Risk disclosure</span><textarea value={form.risk_disclosure} onChange={e=>setForm({...form,risk_disclosure:e.target.value})} placeholder="Risk information shown for this plan"/></label><label className="settings-check"><input type="checkbox" checked={!!form.active} onChange={e=>setForm({...form,active:e.target.checked})}/><span>Visible to members</span></label><div className="plan-admin-actions"><button className="primary compact" disabled={busy} type="submit">{busy?'Saving…':form.id?'Update plan':'Add plan'}</button>{form.id&&<button className="outline-button" type="button" onClick={()=>setForm(blank())}>Cancel</button>}</div></form></section></>;
}

export function AdminSettingsView({token,toast}:any){
  const [rows,setRows]=useState<any[]>([]);
  const [support,setSupport]=useState<any>({support_email:'infolinkbonusinvest@gmail.com',whatsapp_url:'',telegram_url:''});
  const [form,setForm]=useState<any>({country_code:'',bank_name:'',account_name:'',account_number:'',instructions:'',active:true});
  const [busy,setBusy]=useState(false);
  const load=async()=>{try{const [list,settings]=await Promise.all([client(token,'/admin/payment-instructions'),client(token,'/support-settings')]);setRows(list as any[]);setSupport(settings)}catch(e){toast(e instanceof Error?e.message:'Could not load settings')}};
  useEffect(()=>{load()},[token]);
  const savePayment=async(e:React.FormEvent)=>{e.preventDefault();setBusy(true);try{await client(token,'/admin/payment-instructions',{method:'POST',body:JSON.stringify(form)});setForm({country_code:'',bank_name:'',account_name:'',account_number:'',instructions:'',active:true});toast('Payment instructions saved');load()}catch(err){toast(err instanceof Error?err.message:'Could not save instructions')}finally{setBusy(false)}};
  const saveSupport=async(e:React.FormEvent)=>{e.preventDefault();setBusy(true);try{await client(token,'/admin/support-settings',{method:'POST',body:JSON.stringify(support)});toast('Support links saved');load()}catch(err){toast(err instanceof Error?err.message:'Could not save support links')}finally{setBusy(false)}};
  return <><section className="panel settings-panel"><div className="panel-heading"><div><h2>Payment instructions by country</h2><p>Members see these details when they open the deposit form.</p></div><Building2 size={19}/></div><div className="workflow-table"><div className="workflow-head settings-head-grid"><span>Country</span><span>Bank / provider</span><span>Account name</span><span>Account number</span><span>Status</span><span/></div>{rows.map(r=><div className="workflow-row settings-head-grid" key={r.country_code}><b>{countryLabel(r.country_code)} <small>{r.country_code}</small></b><span>{r.bank_name||'—'}</span><span>{r.account_name}</span><span>{r.account_number}</span><span className={`status-tag ${r.active?'':'muted'}`}>{r.active?'Active':'Hidden'}</span><span className="proof-actions"><button className="text-button" onClick={()=>setForm({...r})}>Edit</button></span></div>)}{!rows.length&&<div className="admin-empty-row">No payment instructions configured yet.</div>}</div><form className="settings-form" onSubmit={savePayment}><div className="settings-form-title"><b>Add or edit payment details</b><small>Choose any country, then save the payee details its members must follow.</small></div><label><span>Country</span><select required value={form.country_code} onChange={e=>setForm({...form,country_code:e.target.value})}><option value="">Choose country</option>{form.country_code&&!allCountryCodes.includes(form.country_code)&&<option value={form.country_code}>{countryLabel(form.country_code)} ({form.country_code})</option>}{allCountryCodes.map(c=><option value={c} key={c}>{countryLabel(c)} ({c})</option>)}</select></label><label><span>Bank / provider</span><input value={form.bank_name} onChange={e=>setForm({...form,bank_name:e.target.value})} placeholder="Bank or mobile money"/></label><label><span>Account name</span><input required value={form.account_name} onChange={e=>setForm({...form,account_name:e.target.value})}/></label><label><span>Account number</span><input required value={form.account_number} onChange={e=>setForm({...form,account_number:e.target.value})}/></label><label className="settings-wide"><span>Extra instructions</span><textarea value={form.instructions} onChange={e=>setForm({...form,instructions:e.target.value})} placeholder="Reference format, transfer notes, limits…"/></label><label className="settings-check"><input type="checkbox" checked={form.active!==false} onChange={e=>setForm({...form,active:e.target.checked})}/><span>Show to members</span></label><button className="primary compact" disabled={busy} type="submit"><CheckCircle2 size={15}/> Save payment instructions</button></form></section><section className="panel settings-panel"><div className="panel-heading"><div><h2>Support links</h2><p>These appear on every member’s Profile support card.</p></div><Globe2 size={19}/></div><form className="settings-form support-form" onSubmit={saveSupport}><label><span>Support email</span><input required type="email" value={support.support_email||''} onChange={e=>setSupport({...support,support_email:e.target.value})}/></label><label><span>Telegram group URL</span><input value={support.telegram_url||''} onChange={e=>setSupport({...support,telegram_url:e.target.value})} placeholder="https://t.me/…"/></label><button className="primary compact" disabled={busy} type="submit"><CheckCircle2 size={15}/> Save support links</button></form></section></>;
}

export function AdminWithdrawalMinimums({token,toast}:any){
  const [rows,setRows]=useState<any[]>([]);
  const [form,setForm]=useState({country_code:'',minimum:''});
  const [busy,setBusy]=useState(false);
  const load=async()=>{try{setRows(await client(token,'/admin/withdrawal-minimums') as any[])}catch(error){toast(error instanceof Error?error.message:'Could not load withdrawal minimums')}};
  useEffect(()=>{load()},[token]);
  const selectCountry=(country_code:string)=>{const existing=rows.find(row=>row.country_code===country_code);setForm({country_code,minimum:existing?String(Number(existing.minimum_minor)/100):''})};
  const save=async(event:React.FormEvent<HTMLFormElement>)=>{
    event.preventDefault();
    const minimum=Number(form.minimum);
    if(!form.country_code||!Number.isFinite(minimum)||minimum<=0){toast('Choose a country and enter a minimum greater than zero');return}
    const minimum_minor=Math.round(minimum*100);
    if(!Number.isSafeInteger(minimum_minor)){toast('Enter a valid minimum withdrawal amount');return}
    setBusy(true);
    try{
      await client(token,'/admin/withdrawal-minimums',{method:'POST',body:JSON.stringify({country_code:form.country_code,minimum_minor})});
      setForm({country_code:'',minimum:''});
      toast('Withdrawal minimum saved');
      await load();
    }catch(error){toast(error instanceof Error?error.message:'Could not save withdrawal minimum')}
    finally{setBusy(false)}
  };
  const format=(row:any)=>`${row.currency_code} ${new Intl.NumberFormat(undefined,{minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(row.minimum_minor)/100)}`;
  const countryCurrency=(code:string)=>Object.entries(countryToCurrency).find(([country])=>country===code)?.[1]||'USD';
  return <section className="panel settings-panel">
    <div className="panel-heading"><div><h2>Minimum withdrawals by country</h2><p>Members need at least this available balance before opening a withdrawal request. Countries not configured here cannot request withdrawals.</p></div><Building2 size={19}/></div>
    <div className="workflow-table">
      <div className="workflow-head withdrawal-minimum-grid"><span>Country</span><span>Currency</span><span>Minimum</span><span/></div>
      {rows.map(row=><div className="workflow-row withdrawal-minimum-grid" key={row.country_code}>
        <b>{countryLabel(row.country_code)} <small>{row.country_code}</small></b><span>{row.currency_code}</span><b>{format(row)}</b>
        <span className="proof-actions"><button className="text-button" onClick={()=>selectCountry(row.country_code)}><Pencil size={13}/> Edit</button></span>
      </div>)}
      {!rows.length&&<div className="admin-empty-row">No withdrawal minimums configured.</div>}
    </div>
    <form className="settings-form" onSubmit={save}>
      <div className="settings-form-title"><b>Set a country minimum</b><small>Enter the amount in the country’s currency. Saving an existing country updates its minimum.</small></div>
      <label><span>Country</span><select required value={form.country_code} onChange={event=>selectCountry(event.target.value)}><option value="">Choose country</option>{countryCodes.map(code=><option value={code} key={code}>{countryLabel(code)} ({code})</option>)}</select></label>
      <label><span>Minimum amount ({countryCurrency(form.country_code)})</span><input required type="number" min="0.01" step="0.01" value={form.minimum} onChange={event=>setForm({...form,minimum:event.target.value})}/></label>
      <button className="primary compact" disabled={busy} type="submit"><CheckCircle2 size={15}/>{busy?'Saving…':'Save minimum'}</button>
    </form>
  </section>;
}

export function WithdrawalForm({token,data,money,supportEmail,onDone,onCancel}:any){
  const [minimum,setMinimum]=useState<any>(null);
  const [minimumError,setMinimumError]=useState('');
  const [accountError,setAccountError]=useState('');
  const [accountLoading,setAccountLoading]=useState(true);
  const [source,setSource]=useState('wallet');
  const [amount,setAmount]=useState('');
  const [payoutMethod,setPayoutMethod]=useState('mobile_money');
  const [provider,setProvider]=useState('');
  const [accountName,setAccountName]=useState('');
  const [accountNumber,setAccountNumber]=useState('');
  const [saveAccount,setSaveAccount]=useState(false);
  const [requestId]=useState(()=>crypto.randomUUID());
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState('');
  const sources=[
    {id:'wallet',label:'Wallet balance',available:Number(data.available)||0,detail:'Available to request'},
    {id:'referrals',label:'Referral commissions',available:Number(data.referrals)||0},
    {id:'bonus',label:'Bonuses',available:Number(data.bonus)||0},
    {id:'returns',label:'Investment returns',available:Number(data.returns?.paid_minor||0)/100},
    {id:'other',label:'Other',available:null,detail:'Ask support'},
  ];
  const selectedSource=sources.find(item=>item.id===source)||sources[0];
  const minimumAmount=Number(minimum?.minimum_minor||0)/100;
  const changePayoutMethod=(method:string)=>{
    if(method===payoutMethod)return;
    setPayoutMethod(method);
    setProvider('');
    setAccountNumber('');
  };
  useEffect(()=>{
    let cancelled=false;
    client(token,'/member/withdrawal-minimum')
      .then(result=>{if(!cancelled)setMinimum(result)})
      .catch(reason=>{if(!cancelled)setMinimumError(reason instanceof Error?reason.message:'Could not load the withdrawal minimum')});
    client(token,'/member/withdrawal-account')
      .then((account:any)=>{
        if(cancelled||!account)return;
        setPayoutMethod(account.payout_method);
        setProvider(account.payout_provider);
        setAccountName(account.payout_account_name);
        setAccountNumber(account.payout_account_number);
        setSaveAccount(true);
      })
      .catch(reason=>{if(!cancelled)setAccountError(reason instanceof Error?reason.message:'Could not load saved payout details')})
      .finally(()=>{if(!cancelled)setAccountLoading(false)});
    return()=>{cancelled=true};
  },[token]);
  const submit=async(event:React.FormEvent<HTMLFormElement>)=>{
    event.preventDefault();
    setError('');
    const numericAmount=Number(amount);
    if(minimumError){setError(minimumError);return}
    if(minimum?.configured!==true){setError('A minimum withdrawal amount has not been configured for your country. Please contact support.');return}
    if(!Number.isFinite(numericAmount)||numericAmount<=0){setError('Enter an amount greater than zero');return}
    const amountMinor=Math.round(numericAmount*100);
    if(!Number.isSafeInteger(amountMinor)){setError('Enter a valid withdrawal amount');return}
    if(amountMinor<Number(minimum.minimum_minor)){setError(`The minimum withdrawal is ${minimum.currency_code} ${new Intl.NumberFormat(undefined,{minimumFractionDigits:2,maximumFractionDigits:2}).format(minimumAmount)}`);return}
    if(selectedSource.available!==null&&numericAmount>selectedSource.available){setError(`The amount exceeds your available ${selectedSource.label.toLowerCase()} of ${money(String(selectedSource.available))}`);return}
    if(!provider.trim()||!accountName.trim()||!accountNumber.trim()){setError('Complete the payout provider, account name, and account number');return}

    setBusy(true);
    try{
      if(saveAccount){
        await client(token,'/member/withdrawal-account',{method:'PUT',body:JSON.stringify({
          payout_method:payoutMethod,
          payout_provider:provider.trim(),
          payout_account_name:accountName.trim(),
          payout_account_number:accountNumber.trim(),
        })});
      }
      if(source==='wallet'){
        await client(token,'/member/withdrawals',{method:'POST',body:JSON.stringify({
          request_id:requestId,
          amount_minor:amountMinor,
          asset_code:data.currency,
          payout_method:payoutMethod,
          payout_provider:provider.trim(),
          payout_account_name:accountName.trim(),
          payout_account_number:accountNumber.trim(),
        })});
        window.dispatchEvent(new Event('member-withdrawal-updated'));
        onDone('Withdrawal request submitted. Your balance changes when it is completed.');
      }else{
        const subject=`Withdrawal support request: ${selectedSource.label}`;
        const body=[
          'Hello, I would like to request a withdrawal.',
          `Member: ${data.name} (${data.email})`,
          `Source: ${selectedSource.label}`,
          `Requested amount: ${data.currency} ${numericAmount.toFixed(2)}`,
          `Payout method: ${payoutMethod==='mobile_money'?'Mobile money':'Bank'}`,
          `Provider/bank: ${provider.trim()}`,
          `Account name: ${accountName.trim()}`,
          `Account number/phone: ${accountNumber.trim()}`,
        ].join('\n');
        window.location.href=`mailto:${encodeURIComponent(supportEmail)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
        onDone('Support email draft opened. Send it to submit your request.');
      }
    }catch(reason){setError(reason instanceof Error?reason.message:'Could not submit withdrawal request')}
    finally{setBusy(false)}
  };
  const minimumLoading=!minimum&&!minimumError;
  return <form className="settings-form withdrawal-request-form" onSubmit={submit}>
    <div className="settings-form-title"><b>Withdraw funds</b><small>Choose an amount and payout destination.</small></div>
    {minimumError&&<div className="notice-banner data-error settings-wide" role="alert"><ShieldCheck size={18}/><span><b>Minimum unavailable</b><small>{minimumError}</small></span></div>}
    {minimum?.configured===false&&<div className="notice-banner data-error settings-wide" role="alert"><ShieldCheck size={18}/><span><b>Withdrawals unavailable</b><small>A minimum amount has not been set for your country. Please contact support.</small></span></div>}
    {minimum?.configured===true&&<div className="notice-banner settings-wide"><ShieldCheck size={18}/><span><b>Minimum: {minimum.currency_code} {new Intl.NumberFormat(undefined,{minimumFractionDigits:2,maximumFractionDigits:2}).format(minimumAmount)}</b><small>Pending requests do not change your balance.</small></span></div>}
    {accountError&&<div className="notice-banner data-error settings-wide" role="alert"><ShieldCheck size={18}/><span><b>Saved details unavailable</b><small>You can still enter payout details manually. {accountError}</small></span></div>}
    <div className="withdrawal-field settings-wide"><span className="withdrawal-field-label">Withdraw from</span><div className="withdrawal-choice-grid" role="group" aria-label="Withdrawal source">{sources.map(item=><button type="button" className={`withdrawal-choice ${source===item.id?'selected':''}`} aria-pressed={source===item.id} key={item.id} onClick={()=>setSource(item.id)}><b>{item.label}</b><small>{item.available===null?item.detail||'Support request':money(String(item.available))}</small></button>)}</div></div>
    <label><span>Amount ({data.currency})</span><input required type="number" min={minimum?.configured?minimumAmount:0.01} max={selectedSource.available===null?undefined:selectedSource.available} step="0.01" value={amount} onChange={event=>setAmount(event.target.value)} placeholder="Enter amount"/></label>
    <div className="withdrawal-field"><span className="withdrawal-field-label">Payout method</span><div className="withdrawal-methods" role="group" aria-label="Payout method"><button type="button" className={payoutMethod==='mobile_money'?'selected':''} aria-pressed={payoutMethod==='mobile_money'} onClick={()=>changePayoutMethod('mobile_money')}>Mobile money</button><button type="button" className={payoutMethod==='bank'?'selected':''} aria-pressed={payoutMethod==='bank'} onClick={()=>changePayoutMethod('bank')}>Bank transfer</button></div></div>
    <label><span>{payoutMethod==='mobile_money'?'Mobile-money provider':'Bank name'}</span><input required value={provider} onChange={event=>setProvider(event.target.value)} placeholder={payoutMethod==='mobile_money'?'e.g. MTN, Airtel':'Bank name'}/></label>
    <label><span>Account holder name</span><input required value={accountName} onChange={event=>setAccountName(event.target.value)} placeholder="Name on the account"/></label>
    <label><span>{payoutMethod==='mobile_money'?'Phone number':'Account number'}</span><input required value={accountNumber} onChange={event=>setAccountNumber(event.target.value)} placeholder={payoutMethod==='mobile_money'?'Include country code':'Bank account number'}/></label>
    <label className="withdrawal-save-account settings-wide"><input type="checkbox" checked={saveAccount} onChange={event=>setSaveAccount(event.target.checked)}/><span><b>Save payout details</b><small>Use this name and account next time.</small></span></label>
    {error&&<div className="form-error settings-wide" role="alert">{error}</div>}
    <div className="settings-wide withdrawal-form-actions"><button className="primary compact" type="submit" disabled={busy||minimumLoading||accountLoading||minimum?.configured!==true}>{busy?'Submitting…':source==='wallet'?'Request withdrawal':'Continue by email'}</button><button className="outline-button" type="button" onClick={onCancel}>Cancel</button></div>
  </form>;
}

export function MemberWithdrawalHistory({token,money}:any){
  const [rows,setRows]=useState<any[]>([]);
  const [error,setError]=useState('');
  const load=async()=>{try{setRows(await client(token,'/member/withdrawals') as any[]);setError('')}catch(reason){setError(reason instanceof Error?reason.message:'Could not load withdrawal requests')}};
  useEffect(()=>{
    void load();
    const refresh=()=>{void load()};
    window.addEventListener('member-withdrawal-updated',refresh);
    return()=>window.removeEventListener('member-withdrawal-updated',refresh);
  },[token]);
  return <section className="panel table-panel">
    <div className="panel-heading"><div><h2>Withdrawal requests</h2><p>Track request status and payout details.</p></div><button className="outline-button" onClick={()=>void load()}>Refresh</button></div>
    {error&&<div className="notice-banner data-error" role="alert"><ShieldCheck size={18}/><span><b>Withdrawal history unavailable</b><small>{error}</small></span></div>}
    <div className="workflow-table">
      <div className="workflow-head withdrawal-history-grid"><span>Requested</span><span>Amount</span><span>Payout destination</span><span>Status</span><span>Message</span></div>
      {rows.map(row=><div className="workflow-row withdrawal-history-grid" key={row.id}><span>{dateLabel(row.created_at)}</span><b>{money(String(Number(row.amount_minor)/100))}</b><span>{row.payout_method==='mobile_money'?'Mobile money':'Bank'} · {row.payout_provider}<small>{row.payout_account_name} · {row.payout_account_number}</small></span><span className={`status-tag ${row.status==='approved'?'':'muted'}`}>{row.status==='approved'?'Completed':row.status==='rejected'?'Cancelled':'Pending'}</span><span>{row.admin_note||'—'}</span></div>)}
      {!rows.length&&!error&&<div className="admin-empty-row">No wallet withdrawal requests yet.</div>}
    </div>
  </section>;
}

export function AdminWithdrawalRequestsView({token,toast}:any){
  const [status,setStatus]=useState('pending');
  const [rows,setRows]=useState<any[]>([]);
  const [loading,setLoading]=useState(false);
  const [busy,setBusy]=useState('');
  const [error,setError]=useState('');
  const load=async()=>{
    setLoading(true);
    try{setRows(await client(token,`/admin/withdrawals?status=${status}`) as any[]);setError('')}
    catch(reason){setError(reason instanceof Error?reason.message:'Could not load withdrawal requests')}
    finally{setLoading(false)}
  };
  useEffect(()=>{void load()},[token,status]);
  const review=async(row:any,action:'approve'|'reject')=>{
    if(action==='approve'&&!window.confirm(`Approve and deduct ${row.asset_code} ${(Number(row.amount_minor)/100).toFixed(2)} from ${row.member_name}'s wallet? You must send the payout to the listed destination after approval.`))return;
    const note=action==='reject'?window.prompt('Reason for rejecting this withdrawal?')?.trim()||'':'';
    if(action==='reject'&&!note)return;
    setBusy(row.id);
    try{
      await client(token,`/admin/withdrawals/${row.id}/review`,{method:'POST',body:JSON.stringify({action,note})});
      toast(action==='approve'?'Withdrawal approved and wallet debited. Send payout to the listed destination.':'Withdrawal rejected; wallet balance unchanged.');
      await load();
    }catch(reason){setError(reason instanceof Error?reason.message:'Could not review withdrawal request')}
    finally{setBusy('')}
  };
  return <section className="panel table-panel">
    <div className="table-toolbar"><div><h2>Withdrawal requests</h2><p>Approving a request deducts its amount from the member wallet; transfer the payout manually to the listed account.</p></div><button className="outline-button" onClick={()=>void load()}>Refresh</button></div>
    <div className="tabs admin-tabs">{['pending','approved','rejected','all'].map(item=><button className={status===item?'selected':''} onClick={()=>setStatus(item)} key={item}>{item}</button>)}</div>
    {error&&<div className="notice-banner data-error" role="alert"><ShieldCheck size={18}/><span><b>Withdrawal request action failed</b><small>{error}</small></span></div>}
    {loading&&<div className="inline-loading">Loading withdrawal requests…</div>}
    <div className="workflow-table">
      <div className="workflow-head admin-withdrawal-grid"><span>Member</span><span>Amount</span><span>Payout destination</span><span>Requested</span><span>Status</span><span>Actions</span></div>
      {rows.map(row=><div className="workflow-row admin-withdrawal-grid" key={row.id}>
        <div><b>{row.member_name}</b><small>{row.email}</small></div>
        <b>{row.asset_code} {(Number(row.amount_minor)/100).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2})}</b>
        <span>{row.payout_method==='mobile_money'?'Mobile money':'Bank'} · {row.payout_provider}<small>{row.payout_account_name} · {row.payout_account_number}</small></span>
        <span>{dateLabel(row.created_at)}</span>
        <span className={`status-tag ${row.status==='approved'?'':'muted'}`}>{row.status}{row.admin_note&&<small>{row.admin_note}</small>}</span>
        <span className="proof-actions">{row.status==='pending'?<><button className="text-button" disabled={!!busy} onClick={()=>void review(row,'approve')}><CheckCircle2 size={14}/> Approve & debit</button><button className="text-button muted-link" disabled={!!busy} onClick={()=>void review(row,'reject')}><XCircle size={14}/> Reject</button></>:<span className="muted-link">{row.transaction_id?'Debited on approval':'Reviewed'}</span>}</span>
      </div>)}
      {!rows.length&&!loading&&!error&&<div className="admin-empty-row">No {status==='all'?'':status} withdrawal requests.</div>}
    </div>
  </section>;
}
