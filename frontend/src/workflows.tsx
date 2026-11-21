import {useEffect,useState} from 'react';
import {ArrowRight, Bell, Building2, CheckCircle2, Copy, Gift, Globe2, Image as ImageIcon, Loader2, Mail, MessageCircle, ReceiptText, Send, ShieldCheck, TrendingUp, Upload, X, XCircle} from 'lucide-react';
import {apiUrl,supabase} from './supabase';

const client = async (token:string,path:string,init:RequestInit={}) => {
  const response = await fetch(`${apiUrl}${path}`,{...init,headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`,...(init.headers||{})}});
  const body = await response.json().catch(()=>({}));
  if(!response.ok) throw new Error(body.error||'Request failed');
  return body.data;
};
const minorMoney = (value:any,money:(v:string)=>string) => money(String((Number(value||0)/100).toFixed(2)));
const dateLabel = (value:any) => value?new Date(value).toLocaleString():'Not scheduled';
const DAILY_RATE_BPS = 500;

export function ReturnStrip({returns,money}:any){
  return <section className="return-strip">
    <div className="return-main"><span className="return-icon"><TrendingUp size={19}/></span><div><small>Daily automated return</small><strong>{minorMoney(returns?.daily_minor,money)}</strong><em>{minorMoney(returns?.paid_minor,money)} credited to date</em></div></div>
    <div className="return-stat"><small>Accruing now</small><b>{minorMoney(returns?.accrued_minor,money)}</b><span>Next credit {dateLabel(returns?.next_credit_at)}</span></div>
    <div className="return-note"><ShieldCheck size={16}/><span>Calculated from active plans every time you open your dashboard.</span></div>
  </section>;
}

export function InvestPage({data,money,token,onChoose}:any){
  const [tab,setTab]=useState('Available Plans');
  const [plans,setPlans]=useState<any[]>([]);
  const [rows,setRows]=useState<any[]>([]);
  const [returns,setReturns]=useState<any>(null);
  const [proofs,setProofs]=useState<any[]>([]);
  const [loading,setLoading]=useState(false);
  const [error,setError]=useState('');
  const load=async()=>{setLoading(true);setError('');try{const [p,i,r,pr]=await Promise.all([client(token,'/investment-plans'),client(token,'/member/investments'),client(token,'/member/returns'),client(token,'/member/payment-proofs')]);setPlans(p as any[]);setRows(i as any[]);setReturns(r);setProofs(pr as any[])}catch(e){setError(e instanceof Error?e.message:'Could not load plans')}finally{setLoading(false)}};
  useEffect(()=>{load()},[token]);
  return <>
    <ReturnStrip returns={returns} money={money}/>
    <div className="tabs"> {['Available Plans','My Investments'].map(x=><button className={tab===x?'selected':''} onClick={()=>setTab(x)} key={x}>{x}</button>)}</div>
    {error&&<div className="notice-banner data-error"><ShieldCheck size={18}/><span><b>Plans unavailable</b><small>{error}</small></span></div>}
    {loading&&<div className="inline-loading"><Loader2 size={15} className="spin"/> Loading plans…</div>}
    {tab==='Available Plans'?<>
      <div className="notice-banner"><ShieldCheck size={19}/><span><b>Investment plans</b><small>Earn 5% daily income on your active principal. Your plan activates automatically once your payment proof is verified.</small></span><span className="status-tag">5% DAILY</span></div>
      <div className="plan-grid">{plans.map((p,i)=><article className="plan-card" key={p.id}><div className="plan-top"><span className={`plan-symbol ps${i%4}`}><TrendingUp size={18}/></span><span className="status-tag">{p.duration_days?`${p.duration_days} DAYS`:'FLEXIBLE'}</span></div><h3>{p.name}</h3><div className="plan-amount">{minorMoney(p.minimum_minor,money)} <small>minimum</small></div><div className="plan-details"><span>Daily income <b>{DAILY_RATE_BPS/100}% · {minorMoney(Number(p.minimum_minor)*DAILY_RATE_BPS/10000,money)}</b></span><span>Credit cycle <b>Every {p.roi_interval_hours||24}h</b></span><span>Starts <b>After verification</b></span><span>Duration <b>{p.duration_days?`${p.duration_days} days`:'Flexible'}</b></span></div><button className="plan-button" onClick={()=>onChoose({...p,amount:Number(p.minimum_minor)/100})}>Choose plan <ArrowRight size={15}/></button></article>)}</div>
      {!loading&&!plans.length&&<section className="panel empty-state"><span><TrendingUp/></span><h2>No plans are open yet</h2><p>Administration will publish the available plans shortly.</p></section>}
    </>:<>
      <section className="panel table-panel"><div className="panel-heading"><div><h2>My investments</h2><p>Active positions and their calculated returns.</p></div></div><div className="workflow-table"><div className="workflow-head"><span>Plan</span><span>Principal</span><span>Daily return</span><span>Credited</span><span>Next credit</span><span>Status</span></div>{rows.map(r=><div className="workflow-row" key={r.id}><b>{r.plan}</b><span>{minorMoney(r.principal_minor,money)}</span><span>{minorMoney(Number(r.principal_minor)*Number(r.rate_bps)/10000,money)}</span><span>{minorMoney(r.paid_minor,money)}</span><span>{dateLabel(r.next_roi_at)}</span><span className={`status-tag ${r.status==='active'?'':'muted'}`}>{r.status}</span></div>)}{!rows.length&&!loading&&<div className="admin-empty-row">No investments yet.</div>}</div></section>
      <section className="panel table-panel"><div className="panel-heading"><div><h2>Payment proof submissions</h2><p>Track the deposits you sent for review.</p></div></div><div className="workflow-table"><div className="workflow-head"><span>Reference</span><span>Amount</span><span>Submitted</span><span>Status</span><span>Note</span></div>{proofs.map(p=><div className="workflow-row" key={p.id}><b>{p.provider_reference||p.id.slice(0,8)}</b><span>{minorMoney(p.amount_minor,money)}</span><span>{dateLabel(p.created_at)}</span><span className={`status-tag ${p.status==='approved'?'':'muted'}`}>{p.status}</span><span>{p.rejection_reason||'—'}</span></div>)}{!proofs.length&&!loading&&<div className="admin-empty-row">No proof submissions yet.</div>}</div></section>
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

export function ProofForm({token,data,amount,plan,onDone,onCancel,money}:any){
  const [phone,setPhone]=useState(data?.profile?.phone||'');
  const [payerName,setPayerName]=useState(data?.name||'');
  const [file,setFile]=useState<File|null>(null);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState('');
  const submit=async(e:React.FormEvent)=>{e.preventDefault();setError('');if(!file){setError('Attach a payment screenshot');return}if(!supabase){setError('Upload service is unavailable');return}setBusy(true);try{const {data:auth}=await supabase.auth.getUser();const user=auth.user;if(!user)throw new Error('Sign in again to upload');const path=`${user.id}/${Date.now()}-${file.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;const upload=await supabase.storage.from('payment-proofs').upload(path,file,{contentType:file.type,upsert:false});if(upload.error)throw upload.error;await client(token,'/member/payment-proofs',{method:'POST',body:JSON.stringify({amount_minor:Math.round(Number(amount)*100),asset_code:data?.currency||'RWF',screenshot_path:path,phone,full_name:payerName,payer_name:payerName,plan_id:plan?.id||null})});onDone()}catch(err){setError(err instanceof Error?err.message:'Could not submit proof')}finally{setBusy(false)}};
  return <form className="proof-form" onSubmit={submit}><div className="proof-summary"><ReceiptText size={20}/><div><b>{plan?`${plan.name} plan`:'Deposit'}</b><small>{money(String(amount||0))} · Your plan activates automatically after verification</small></div></div><div className="proof-fields"><label><span>Name used to pay</span><input required value={payerName} onChange={e=>setPayerName(e.target.value)} placeholder="Name shown on the payment"/></label><label><span>Number used to pay</span><input required value={phone} onChange={e=>setPhone(e.target.value)} placeholder="Phone or payment number"/></label><label><span>Payment screenshot</span><input required type="file" accept="image/*" onChange={e=>setFile(e.target.files?.[0]||null)}/></label></div>{file&&<div className="proof-preview"><ImageIcon size={15}/> {file.name}</div>}{error&&<div className="form-error">{error}</div>}<div className="proof-actions"><button className="primary compact" disabled={busy} type="submit"><Upload size={15}/> {busy?'Submitting…':'Submit proof'}</button><button className="outline-button" type="button" onClick={onCancel}>Cancel</button></div></form>;
}

export function AdminProofsView({token,toast}:any){
  const [status,setStatus]=useState('pending');
  const [rows,setRows]=useState<any[]>([]);
  const [links,setLinks]=useState<Record<string,string>>({});
  const [loading,setLoading]=useState(false);
  const [busy,setBusy]=useState('');
  const load=async()=>{setLoading(true);try{const d=await client(token,`/admin/payment-proofs?status=${encodeURIComponent(status)}`);const list=(d as any).rows||[];setRows(list as any[]);const storage=supabase?.storage;if(storage){const pairs=await Promise.all(list.map(async(r:any)=>{const {data}=await storage.from('payment-proofs').createSignedUrl(r.screenshot_path,3600);return [r.id,data?.signedUrl||''] as const}));setLinks(Object.fromEntries(pairs))}}catch{}finally{setLoading(false)}};
  useEffect(()=>{load()},[token,status]);
  const review=async(id:string,action:string)=>{const note=action==='approve'?'':window.prompt(action==='reject'?'Reason for rejection':'Reason for cancellation')||'';if(action!=='approve'&&!note)return;setBusy(id);try{await client(token,`/admin/payment-proofs/${id}/review`,{method:'POST',body:JSON.stringify({action,note})});toast(action==='approve'?'Proof approved · plan activated and counting':`Proof ${action==='reject'?'rejected':'cancelled'}`);load()}catch(e){toast(e instanceof Error?e.message:'Review failed')}finally{setBusy('')}};
  return <section className="panel table-panel"><div className="table-toolbar"><div><h2>Payment proofs</h2><p>Review deposit evidence submitted by members.</p></div><button className="outline-button" onClick={load}>Refresh</button></div><div className="tabs admin-tabs">{['pending','approved','rejected','cancelled','all'].map(x=><button className={status===x?'selected':''} onClick={()=>setStatus(x)} key={x}>{x}</button>)}</div><div className="workflow-table"><div className="workflow-head"><span>Member</span><span>Amount</span><span>Details</span><span>Proof</span><span>Status</span><span>Review</span></div>{rows.map(r=><div className="workflow-row" key={r.id}><div className="user-cell"><span className="avatar small">{String(r.name||'U').slice(0,1).toUpperCase()}</span><div><b>{r.name}</b><small>{r.email}</small></div></div><b>{r.asset_code} {String(Number(r.amount_minor||0)/100)}</b><span>{r.payer_name||'—'}<small>{r.phone||'—'}</small></span><span>{links[r.id]?<a href={links[r.id]} target="_blank" rel="noreferrer" className="muted-link">View screenshot</a>:'Screenshot'}</span><span className={`status-tag ${r.status==='approved'?'':'muted'}`}>{r.status}</span><span className="proof-actions">{r.status==='pending'?<><button className="text-button" disabled={!!busy} onClick={()=>review(r.id,'approve')}><CheckCircle2 size={14}/> Approve</button><button className="text-button" disabled={!!busy} onClick={()=>review(r.id,'reject')}><XCircle size={14}/> Reject</button><button className="text-button muted-link" disabled={!!busy} onClick={()=>review(r.id,'cancel')}>Cancel</button></>:<span className="muted-link">{r.rejection_reason||'Reviewed'}</span>}</span></div>)}{!rows.length&&!loading&&<div className="admin-empty-row">No {status==='all'?'':status} payment proofs.</div>}</div></section>;
}

const countryNames = (()=>{try{return new Intl.DisplayNames(['en'],{type:'region'})}catch{return null}})();
const countryLabel = (code:string)=>code?countryNames?.of(code.toUpperCase())||code.toUpperCase():'your country';
const countryOptions = ['RW','CD','BI','ZM','ZA','KE','TZ','UG','DE','US','GB','FR','CA','NG','GH','SN','CI','CM','MA','EG','IN','AE','SA','CN','JP','AU'];

export function NotificationBell({token,toast}:any){
  const [rows,setRows]=useState<any[]>([]);
  const [open,setOpen]=useState(false);
  const load=()=>client(token,'/member/notifications').then(d=>setRows(d as any[])).catch(()=>{});
  useEffect(()=>{load();const timer=setInterval(load,60000);return()=>clearInterval(timer)},[token]);
  const unread=rows.filter(r=>!r.read).length;
  const mark=async(id:string)=>{try{await client(token,`/member/notifications/${id}/read`,{method:'POST'});setRows(current=>current.map(r=>r.id===id?{...r,read:true}:r))}catch(e){toast(e instanceof Error?e.message:'Could not mark notification')}};
  return <div className="notification-wrap"><button className="icon-button bell-button" aria-label="Notifications" aria-expanded={open} onClick={()=>setOpen(!open)}><Bell size={18}/>{unread>0&&<span className="bell-badge">{unread}</span>}</button>{open&&<><button className="notification-backdrop" aria-label="Close notifications" onClick={()=>setOpen(false)}/><div className="notification-menu"><div className="notification-head"><b>Notifications</b><small>{unread} unread</small></div><div className="notification-list">{rows.map(r=><button className={`notification-item ${r.read?'':'unread'}`} key={r.id} onClick={()=>mark(r.id)}><span><b>{r.title}</b><small>{dateLabel(r.created_at)}</small></span><p>{r.body}</p>{!r.read&&<em>Mark as read</em>}</button>)}{!rows.length&&<div className="admin-empty-row">No notifications yet.</div>}</div></div></>}</div>;
}

export function PaymentInstructions({token,country}:any){
  const [row,setRow]=useState<any>(null);
  useEffect(()=>{setRow(null);client(token,`/payment-instructions?country=${encodeURIComponent(String(country||''))}`).then(setRow).catch(()=>setRow({configured:false}))},[token,country]);
  if(!row)return <div className="inline-loading"><Loader2 size={15} className="spin"/> Loading payment details…</div>;
  if(!row.configured)return <div className="notice-banner"><ShieldCheck size={18}/><span><b>Payment instructions pending</b><small>Administration has not published deposit details for {countryLabel(String(country||''))} yet. Contact support for help.</small></span></div>;
  return <section className="panel payment-instructions"><div className="panel-heading"><div><h2>Pay for {countryLabel(row.country_code)}</h2><p>Use these details for deposits, then submit your proof below.</p></div><span className="status-tag">VERIFIED PAYEE</span></div><div className="payment-detail-grid"><div><small>Account name</small><b>{row.account_name}</b></div><div><small>Account number</small><b>{row.account_number}</b></div><div><small>Bank / provider</small><b>{row.bank_name||'Not specified'}</b></div></div>{row.instructions&&<p className="payment-note">{row.instructions}</p>}</section>;
}

export function SupportCard({token}:any){
  const [settings,setSettings]=useState<any>(null);
  useEffect(()=>{client(token,'/support-settings').then(setSettings).catch(()=>setSettings({support_email:'infolinkbonusinvest@gmail.com'}))},[token]);
  const email=settings?.support_email||'infolinkbonusinvest@gmail.com';
  return <section className="panel support-panel"><div className="support-panel-head"><span><MessageCircle size={20}/></span><div><h2>Help & support</h2><p>Reach the team or join the community groups.</p></div></div><div className="support-actions"><a className="support-action" href={`mailto:${email}?subject=LINK%20BONUS%20support`}><Mail size={17}/><span><b>Contact us via email</b><small>{email}</small></span></a>{settings?.whatsapp_url?<a className="support-action" href={settings.whatsapp_url} target="_blank" rel="noreferrer"><MessageCircle size={17}/><span><b>Join WhatsApp group</b><small>Open the member community chat</small></span></a>:<button className="support-action disabled" disabled><MessageCircle size={17}/><span><b>Join WhatsApp group</b><small>Link not set by administration</small></span></button>}{settings?.telegram_url?<a className="support-action" href={settings.telegram_url} target="_blank" rel="noreferrer"><Send size={17}/><span><b>Join Telegram group</b><small>Open the member announcements channel</small></span></a>:<button className="support-action disabled" disabled><Send size={17}/><span><b>Join Telegram group</b><small>Link not set by administration</small></span></button>}</div></section>;
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

export function AdminSettingsView({token,toast}:any){
  const [rows,setRows]=useState<any[]>([]);
  const [support,setSupport]=useState<any>({support_email:'infolinkbonusinvest@gmail.com',whatsapp_url:'',telegram_url:''});
  const [form,setForm]=useState<any>({country_code:'',bank_name:'',account_name:'',account_number:'',instructions:'',active:true});
  const [busy,setBusy]=useState(false);
  const load=async()=>{try{const [list,settings]=await Promise.all([client(token,'/admin/payment-instructions'),client(token,'/support-settings')]);setRows(list as any[]);setSupport(settings)}catch(e){toast(e instanceof Error?e.message:'Could not load settings')}};
  useEffect(()=>{load()},[token]);
  const savePayment=async(e:React.FormEvent)=>{e.preventDefault();setBusy(true);try{await client(token,'/admin/payment-instructions',{method:'POST',body:JSON.stringify(form)});setForm({country_code:'',bank_name:'',account_name:'',account_number:'',instructions:'',active:true});toast('Payment instructions saved');load()}catch(err){toast(err instanceof Error?err.message:'Could not save instructions')}finally{setBusy(false)}};
  const saveSupport=async(e:React.FormEvent)=>{e.preventDefault();setBusy(true);try{await client(token,'/admin/support-settings',{method:'POST',body:JSON.stringify(support)});toast('Support links saved');load()}catch(err){toast(err instanceof Error?err.message:'Could not save support links')}finally{setBusy(false)}};
  return <><section className="panel settings-panel"><div className="panel-heading"><div><h2>Payment instructions by country</h2><p>Members see these details when they open the deposit form.</p></div><Building2 size={19}/></div><div className="workflow-table"><div className="workflow-head settings-head-grid"><span>Country</span><span>Bank / provider</span><span>Account name</span><span>Account number</span><span>Status</span><span/></div>{rows.map(r=><div className="workflow-row settings-head-grid" key={r.country_code}><b>{countryLabel(r.country_code)} <small>{r.country_code}</small></b><span>{r.bank_name||'—'}</span><span>{r.account_name}</span><span>{r.account_number}</span><span className={`status-tag ${r.active?'':'muted'}`}>{r.active?'Active':'Hidden'}</span><span className="proof-actions"><button className="text-button" onClick={()=>setForm({...r})}>Edit</button></span></div>)}{!rows.length&&<div className="admin-empty-row">No payment instructions configured yet.</div>}</div><form className="settings-form" onSubmit={savePayment}><label><span>Country code</span><input required value={form.country_code} onChange={e=>setForm({...form,country_code:e.target.value.toUpperCase().slice(0,2)})} list="settings-countries" placeholder="RW"/></label><label><span>Bank / provider</span><input value={form.bank_name} onChange={e=>setForm({...form,bank_name:e.target.value})} placeholder="Bank or mobile money"/></label><label><span>Account name</span><input required value={form.account_name} onChange={e=>setForm({...form,account_name:e.target.value})}/></label><label><span>Account number</span><input required value={form.account_number} onChange={e=>setForm({...form,account_number:e.target.value})}/></label><label className="settings-wide"><span>Extra instructions</span><textarea value={form.instructions} onChange={e=>setForm({...form,instructions:e.target.value})} placeholder="Reference format, transfer notes, limits…"/></label><label className="settings-check"><input type="checkbox" checked={form.active!==false} onChange={e=>setForm({...form,active:e.target.checked})}/><span>Show to members</span></label><button className="primary compact" disabled={busy} type="submit"><CheckCircle2 size={15}/> Save payment instructions</button></form><datalist id="settings-countries">{countryOptions.map(c=><option value={c} key={c}>{countryLabel(c)}</option>)}</datalist></section><section className="panel settings-panel"><div className="panel-heading"><div><h2>Support links</h2><p>These appear on every member’s Profile support card.</p></div><Globe2 size={19}/></div><form className="settings-form support-form" onSubmit={saveSupport}><label><span>Support email</span><input required type="email" value={support.support_email||''} onChange={e=>setSupport({...support,support_email:e.target.value})}/></label><label><span>WhatsApp group URL</span><input value={support.whatsapp_url||''} onChange={e=>setSupport({...support,whatsapp_url:e.target.value})} placeholder="https://chat.whatsapp.com/…"/></label><label><span>Telegram group URL</span><input value={support.telegram_url||''} onChange={e=>setSupport({...support,telegram_url:e.target.value})} placeholder="https://t.me/…"/></label><button className="primary compact" disabled={busy} type="submit"><CheckCircle2 size={15}/> Save support links</button></form></section></>;
}
