import {useEffect,useState} from 'react';
import {ArrowRight,CheckCircle2,Copy,Gift,Image as ImageIcon,Loader2,Mail,ReceiptText,ShieldCheck,TrendingUp,Upload,X,XCircle} from 'lucide-react';
import {apiUrl,supabase} from './supabase';

const client = async (token:string,path:string,init:RequestInit={}) => {
  const response = await fetch(`${apiUrl}${path}`,{...init,headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`,...(init.headers||{})}});
  const body = await response.json().catch(()=>({}));
  if(!response.ok) throw new Error(body.error||'Request failed');
  return body.data;
};
const minorMoney = (value:any,money:(v:string)=>string) => money(String((Number(value||0)/100).toFixed(2)));
const dateLabel = (value:any) => value?new Date(value).toLocaleString():'Not scheduled';

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
      <div className="notice-banner"><ShieldCheck size={19}/><span><b>Investment plans</b><small>Review the terms, fees and risks before choosing a plan. Returns are not guaranteed.</small></span><span className="status-tag">REVIEW</span></div>
      <div className="plan-grid">{plans.map((p,i)=><article className="plan-card" key={p.id}><div className="plan-top"><span className={`plan-symbol ps${i%4}`}><TrendingUp size={18}/></span><span className="status-tag">{p.duration_days?`${p.duration_days} DAYS`:'FLEXIBLE'}</span></div><h3>{p.name}</h3><div className="plan-amount">{minorMoney(p.minimum_minor,money)} <small>minimum</small></div><div className="plan-details"><span>Return interval <b>{p.roi_interval_hours}h</b></span><span>Indicative daily <b>{minorMoney(Number(p.minimum_minor)*Number(p.roi_rate_bps)/10000,money)}</b></span><span>Applicable fees <b>{p.fee_bps?`${Number(p.fee_bps)/100}%`:'None'}</b></span><span>Risk <b>Capital at risk</b></span></div><button className="plan-button" onClick={()=>onChoose({...p,amount:Number(p.minimum_minor)/100})}>Choose plan <ArrowRight size={15}/></button></article>)}</div>
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
  const [fullName,setFullName]=useState(data?.name||'');
  const [payerName,setPayerName]=useState(data?.name||'');
  const [payeeName,setPayeeName]=useState('');
  const [reference,setReference]=useState('');
  const [note,setNote]=useState('');
  const [file,setFile]=useState<File|null>(null);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState('');
  const submit=async(e:React.FormEvent)=>{e.preventDefault();setError('');if(!file){setError('Attach a payment screenshot');return}if(!supabase){setError('Upload service is unavailable');return}setBusy(true);try{const {data:auth}=await supabase.auth.getUser();const user=auth.user;if(!user)throw new Error('Sign in again to upload');const path=`${user.id}/${Date.now()}-${file.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;const upload=await supabase.storage.from('payment-proofs').upload(path,file,{contentType:file.type,upsert:false});if(upload.error)throw upload.error;await client(token,'/member/payment-proofs',{method:'POST',body:JSON.stringify({amount_minor:Math.round(Number(amount)*100),asset_code:data?.currency||'RWF',screenshot_path:path,phone,full_name:fullName,payer_name:payerName,payee_name:payeeName||null,provider_reference:reference||null,note:note||null,plan_id:plan?.id||null})});onDone()}catch(err){setError(err instanceof Error?err.message:'Could not submit proof')}finally{setBusy(false)}};
  return <form className="proof-form" onSubmit={submit}><div className="proof-summary"><ReceiptText size={20}/><div><b>{plan?`${plan.name} plan`:'Deposit'}</b><small>{money(String(amount||0))} · Administration will review your proof</small></div></div><div className="proof-fields"><label><span>Account name</span><input required value={fullName} onChange={e=>setFullName(e.target.value)} placeholder="Name on your account"/></label><label><span>Phone number</span><input required value={phone} onChange={e=>setPhone(e.target.value)} placeholder="+250 …"/></label><label><span>Payer name</span><input required value={payerName} onChange={e=>setPayerName(e.target.value)} placeholder="Name on the payment"/></label><label><span>Receiver name</span><input value={payeeName} onChange={e=>setPayeeName(e.target.value)} placeholder="Optional"/></label><label><span>Payment reference</span><input value={reference} onChange={e=>setReference(e.target.value)} placeholder="Optional transaction ID"/></label><label><span>Screenshot</span><input required type="file" accept="image/*" onChange={e=>setFile(e.target.files?.[0]||null)}/></label></div><label className="proof-note"><span>Note for administration</span><textarea value={note} onChange={e=>setNote(e.target.value)} placeholder="Optional details"/></label>{file&&<div className="proof-preview"><ImageIcon size={15}/> {file.name}</div>}{error&&<div className="form-error">{error}</div>}<div className="proof-actions"><button className="primary compact" disabled={busy} type="submit"><Upload size={15}/> {busy?'Submitting…':'Submit proof'}</button><button className="outline-button" type="button" onClick={onCancel}>Cancel</button></div></form>;
}

export function AdminProofsView({token,toast}:any){
  const [status,setStatus]=useState('pending');
  const [rows,setRows]=useState<any[]>([]);
  const [links,setLinks]=useState<Record<string,string>>({});
  const [loading,setLoading]=useState(false);
  const [busy,setBusy]=useState('');
  const load=async()=>{setLoading(true);try{const d=await client(token,`/admin/payment-proofs?status=${encodeURIComponent(status)}`);const list=(d as any).rows||[];setRows(list as any[]);const storage=supabase?.storage;if(storage){const pairs=await Promise.all(list.map(async(r:any)=>{const {data}=await storage.from('payment-proofs').createSignedUrl(r.screenshot_path,3600);return [r.id,data?.signedUrl||''] as const}));setLinks(Object.fromEntries(pairs))}}catch{}finally{setLoading(false)}};
  useEffect(()=>{load()},[token,status]);
  const review=async(id:string,action:string)=>{const note=action==='approve'?'':window.prompt(action==='reject'?'Reason for rejection':'Reason for cancellation')||'';if(action!=='approve'&&!note)return;setBusy(id);try{await client(token,`/admin/payment-proofs/${id}/review`,{method:'POST',body:JSON.stringify({action,note})});toast(`Proof ${action==='approve'?'approved':action==='reject'?'rejected':'cancelled'}`);load()}catch(e){toast(e instanceof Error?e.message:'Review failed')}finally{setBusy('')}};
  return <section className="panel table-panel"><div className="table-toolbar"><div><h2>Payment proofs</h2><p>Review deposit evidence submitted by members.</p></div><button className="outline-button" onClick={load}>Refresh</button></div><div className="tabs admin-tabs">{['pending','approved','rejected','cancelled','all'].map(x=><button className={status===x?'selected':''} onClick={()=>setStatus(x)} key={x}>{x}</button>)}</div><div className="workflow-table"><div className="workflow-head"><span>Member</span><span>Amount</span><span>Details</span><span>Proof</span><span>Status</span><span>Review</span></div>{rows.map(r=><div className="workflow-row" key={r.id}><div className="user-cell"><span className="avatar small">{String(r.name||'U').slice(0,1).toUpperCase()}</span><div><b>{r.name}</b><small>{r.email}</small></div></div><b>{r.asset_code} {String(Number(r.amount_minor||0)/100)}</b><span>{r.payer_name||'—'}<small>{r.phone||'—'}</small></span><span>{links[r.id]?<a href={links[r.id]} target="_blank" rel="noreferrer" className="muted-link">View screenshot</a>:'Screenshot'}</span><span className={`status-tag ${r.status==='approved'?'':'muted'}`}>{r.status}</span><span className="proof-actions">{r.status==='pending'?<><button className="text-button" disabled={!!busy} onClick={()=>review(r.id,'approve')}><CheckCircle2 size={14}/> Approve</button><button className="text-button" disabled={!!busy} onClick={()=>review(r.id,'reject')}><XCircle size={14}/> Reject</button><button className="text-button muted-link" disabled={!!busy} onClick={()=>review(r.id,'cancel')}>Cancel</button></>:<span className="muted-link">{r.rejection_reason||'Reviewed'}</span>}</span></div>)}{!rows.length&&!loading&&<div className="admin-empty-row">No {status==='all'?'':status} payment proofs.</div>}</div></section>;
}
