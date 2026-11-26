import {useEffect,useRef,useState,type FormEvent} from 'react';
import {Check,ChevronLeft,ChevronRight,Coins,TrendingUp,Wallet,X} from 'lucide-react';
import countryToCurrency from 'country-to-currency';
import {CountrySelect} from './CountrySelect';
import {apiUrl} from './supabase';

type User = {
  id:string;
  name:string;
  email:string;
  country:string|null;
  phone:string|null;
  status:string;
  verification_status:string;
  balance_asset_code:string;
  balance_minor:string|number;
  invested_minor:string|number;
  bonus_minor:string|number;
  referral_minor:string|number;
  portfolio_minor:string|number;
  created_at:string;
};

type Values = {
  full_name:string;
  country:string;
  phone:string;
  status:string;
  verification_status:string;
  wallet_target:string;
  bonus_target:string;
};

type Investment = {
  id:string;
  plan:string;
  amount:string;
  principal_minor:string|number;
  asset_code:string;
  status:string;
  creation_source:string;
  admin_funding_method:string|null;
  date:string;
};

type Props = {
  user:User;
  saving:boolean;
  token:string;
  plans:any[];
  plansLoading:boolean;
  plansError:string;
  onClose:()=>void;
  onSave:(values:Values)=>Promise<void>;
  onUpdateInvested:(amount:string)=>Promise<void>;
  onCreateInvestment:(values:{plan_id:string;amount:string;request_id:string})=>Promise<void>;
  onFinancialChange:(message:string)=>void;
};

const amountFromMinor=(value:string|number)=>{
  const minor=BigInt(String(value||0));
  return `${minor/100n}.${String(minor%100n).padStart(2,'0')}`;
};
const assetForCountry=(country:string)=>{
  const code=country.trim().toUpperCase();
  const countryCode=code==='RWANDA'?'RW':code==='BURUNDI'?'BI':code;
  return countryToCurrency[countryCode as keyof typeof countryToCurrency]??'USD';
};
const formatMoney=(value:string|number,asset:string)=>{
  const minor=BigInt(String(value||0));
  return `${asset} ${new Intl.NumberFormat().format(minor/100n)}.${String(minor%100n).padStart(2,'0')}`;
};
const formatDate=(value:string)=>value?new Intl.DateTimeFormat(undefined,{dateStyle:'medium'}).format(new Date(value)):'—';

export function AdminUserEditor({user,saving,token,plans,plansLoading,plansError,onClose,onSave,onUpdateInvested,onCreateInvestment,onFinancialChange}:Props){
  const [displayUser,setDisplayUser]=useState(user);
  const [values,setValues]=useState<Values>({
    full_name:user.name||'',
    country:user.country||'',
    phone:user.phone||'',
    status:user.status,
    verification_status:user.verification_status||'unverified',
    wallet_target:amountFromMinor(user.balance_minor),
    bonus_target:amountFromMinor(user.bonus_minor),
  });
  const [investedTarget,setInvestedTarget]=useState(amountFromMinor(user.invested_minor));
  const [error,setError]=useState('');
  const [investedError,setInvestedError]=useState('');
  const [investmentPlanId,setInvestmentPlanId]=useState('');
  const [investmentAmount,setInvestmentAmount]=useState('');
  const [investmentRequestId,setInvestmentRequestId]=useState(()=>crypto.randomUUID());
  const [investmentError,setInvestmentError]=useState('');
  const [userInvestments,setUserInvestments]=useState<{total:number;rows:Investment[]}>({total:0,rows:[]});
  const [investmentPage,setInvestmentPage]=useState(1);
  const investmentPageSize=10;
  const [investmentsLoading,setInvestmentsLoading]=useState(false);
  const [investmentsError,setInvestmentsError]=useState('');
  const [summaryError,setSummaryError]=useState('');
  const [investmentAction,setInvestmentAction]=useState<{id:string;mode:'edit'|'cancel'}|null>(null);
  const [investmentActionAmount,setInvestmentActionAmount]=useState('');
  const [investmentActionReason,setInvestmentActionReason]=useState('');
  const [investmentActionRequestId,setInvestmentActionRequestId]=useState('');
  const [investmentActionError,setInvestmentActionError]=useState('');
  const [investmentActionBusy,setInvestmentActionBusy]=useState(false);
  const investmentListRequest=useRef(0);
  const investmentTotalPages=Math.max(1,Math.ceil(userInvestments.total/investmentPageSize));
  const zeroInvestmentAmount=investmentAction?.mode==='edit'&&investmentActionAmount.trim()!==''&&Number(investmentActionAmount)===0;
  const investmentActionCancelling=investmentAction?.mode==='cancel'||zeroInvestmentAmount;
  const availablePlans=plans.filter(plan=>plan.active&&(!plan.country_code||plan.country_code.toUpperCase()===String(user.country||'').toUpperCase()));
  const selectedPlan=availablePlans.find(plan=>plan.id===investmentPlanId);
  const currencyChanged=assetForCountry(values.country)!==user.balance_asset_code;

  const request=async(path:string,init:RequestInit={})=>{
    const response=await fetch(`${apiUrl}${path}`,{...init,headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`,...(init.headers||{})}});
    const body=await response.json().catch(()=>({}));
    if(!response.ok)throw new Error(body.error||'Request failed');
    return body.data;
  };
  const refreshUserSummary=async()=>{
    setSummaryError('');
    try{
      const query=new URLSearchParams({search:user.id,limit:'1',offset:'0'});
      const result=await request(`/admin/users?${query}`);
      const refreshed=result?.rows?.[0] as User|undefined;
      if(!refreshed)throw new Error("Could not reload this member's dashboard values");
      setDisplayUser(refreshed);
      setValues(current=>({
        ...current,
        wallet_target:current.wallet_target===amountFromMinor(displayUser.balance_minor)?amountFromMinor(refreshed.balance_minor):current.wallet_target,
        bonus_target:current.bonus_target===amountFromMinor(displayUser.bonus_minor)?amountFromMinor(refreshed.bonus_minor):current.bonus_target,
      }));
      setInvestedTarget(current=>current===amountFromMinor(displayUser.invested_minor)?amountFromMinor(refreshed.invested_minor):current);
    }catch(reason){setSummaryError(reason instanceof Error?reason.message:"Could not refresh this member's dashboard values")}
  };
  const loadUserInvestments=async()=>{
    const requestId=++investmentListRequest.current;
    setInvestmentsLoading(true);
    setInvestmentsError('');
    try{
      const query=new URLSearchParams({limit:String(investmentPageSize),offset:String((investmentPage-1)*investmentPageSize)});
      const result=await request(`/admin/users/${user.id}/investments?${query}`);
      if(requestId===investmentListRequest.current)setUserInvestments(result??{total:0,rows:[]});
    }catch(reason){if(requestId===investmentListRequest.current)setInvestmentsError(reason instanceof Error?reason.message:"Could not load this member's investments")}
    finally{if(requestId===investmentListRequest.current)setInvestmentsLoading(false)}
  };

  useEffect(()=>{
    setDisplayUser(user);
    setUserInvestments({total:0,rows:[]});
    setValues({
      full_name:user.name||'',
      country:user.country||'',
      phone:user.phone||'',
      status:user.status,
      verification_status:user.verification_status||'unverified',
      wallet_target:amountFromMinor(user.balance_minor),
      bonus_target:amountFromMinor(user.bonus_minor),
    });
    setInvestedTarget(amountFromMinor(user.invested_minor));
    setInvestmentPage(1);
  },[user.id]);

  useEffect(()=>{void loadUserInvestments()},[user.id,token,investmentPage]);

  useEffect(()=>{
    if(!availablePlans.some(plan=>plan.id===investmentPlanId)){
      const first=availablePlans[0];
      if((first?.id||'')===investmentPlanId)return;
      setInvestmentPlanId(first?.id||'');
      setInvestmentAmount(first?(Number(first.minimum_minor||0)/100).toFixed(2):'');
      setInvestmentRequestId(crypto.randomUUID());
    }
  },[availablePlans,investmentPlanId]);

  useEffect(()=>{
    const closeOnEscape=(event:KeyboardEvent)=>{
      if(event.key==='Escape'&&!saving&&!investmentActionBusy)onClose();
    };
    window.addEventListener('keydown',closeOnEscape);
    return()=>window.removeEventListener('keydown',closeOnEscape);
  },[onClose,saving,investmentActionBusy]);

  const update=(key:keyof Values,value:string)=>setValues(current=>({...current,[key]:value}));
  const submit=async(event:FormEvent<HTMLFormElement>)=>{
    event.preventDefault();
    setError('');
    try{await onSave(values)}
    catch(reason){setError(reason instanceof Error?reason.message:'Could not update this user')}
  };
  const submitInvestment=async(event:FormEvent<HTMLFormElement>)=>{
    event.preventDefault();
    setInvestmentError('');
    try{
      await onCreateInvestment({plan_id:investmentPlanId,amount:investmentAmount,request_id:investmentRequestId});
      setInvestmentRequestId(crypto.randomUUID());
      if(investmentPage!==1)setInvestmentPage(1);
      else await loadUserInvestments();
      await refreshUserSummary();
    }
    catch(reason){setInvestmentError(reason instanceof Error?reason.message:'Could not create this investment')}
  };
  const updateInvested=async()=>{
    setInvestedError('');
    try{await onUpdateInvested(investedTarget);await refreshUserSummary()}
    catch(reason){setInvestedError(reason instanceof Error?reason.message:'Could not update invested total')}
  };
  const startInvestmentAction=(investment:Investment,mode:'edit'|'cancel')=>{
    setInvestmentAction({id:investment.id,mode});
    setInvestmentActionAmount(investment.amount);
    setInvestmentActionReason('');
    setInvestmentActionRequestId(crypto.randomUUID());
    setInvestmentActionError('');
  };
  const submitInvestmentAction=async(event:FormEvent<HTMLFormElement>)=>{
    event.preventDefault();
    if(!investmentAction)return;
    setInvestmentActionBusy(true);
    setInvestmentActionError('');
    try{
      const path=`/admin/investments/${investmentAction.id}`;
      const cancelling=investmentAction.mode==='cancel'||zeroInvestmentAmount;
      if(cancelling){
        await request(path,{method:'DELETE',body:JSON.stringify({reason:investmentActionReason,request_id:investmentActionRequestId})});
      }else{
        await request(path,{method:'PATCH',body:JSON.stringify({amount:investmentActionAmount,reason:investmentActionReason,request_id:investmentActionRequestId})});
      }
      const message=cancelling?'Investment cancelled; history retained':'Investment amount updated';
      setInvestmentAction(null);
      setInvestmentActionRequestId('');
      await loadUserInvestments();
      await refreshUserSummary();
      onFinancialChange(message);
    }catch(reason){setInvestmentActionError(reason instanceof Error?reason.message:'Could not update this investment')}
    finally{setInvestmentActionBusy(false)}
  };

  return <div className="modal-backdrop admin-user-editor-backdrop" onClick={()=>!saving&&!investmentActionBusy&&onClose()}>
    <section className="admin-user-editor" role="dialog" aria-modal="true" aria-labelledby="admin-user-editor-title" onClick={event=>event.stopPropagation()}>
      <header className="admin-user-editor-header">
        <div>
          <span className="eyebrow">MEMBER ACCOUNT</span>
          <h2 id="admin-user-editor-title">Update {user.name}</h2>
          <p>{user.email}</p>
        </div>
        <button type="button" className="icon-button" aria-label="Close update form" disabled={saving||investmentActionBusy} onClick={onClose}><X size={18}/></button>
      </header>
      <form onSubmit={submit}>
        <div className="admin-user-editor-grid">
          <label><span>Full name</span><input required value={values.full_name} onChange={event=>update('full_name',event.target.value)}/></label>
          <label><span>Phone</span><input value={values.phone} onChange={event=>update('phone',event.target.value)}/></label>
          <label><span>Country</span><CountrySelect value={values.country} onChange={country=>update('country',country)}/></label>
          <label><span>Verification</span><select value={values.verification_status} onChange={event=>update('verification_status',event.target.value)}>
            {!['unverified','pending','verified','rejected'].includes(values.verification_status)&&<option value={values.verification_status}>{values.verification_status}</option>}
            <option value="unverified">Unverified</option><option value="pending">Pending</option><option value="verified">Verified</option><option value="rejected">Rejected</option>
          </select></label>
          <label><span>Account</span><select value={values.status} onChange={event=>update('status',event.target.value)}>
            <option value="active">Active</option><option value="suspended">Suspended</option>
          </select></label>
          <label><span>Registration date</span><input value={formatDate(user.created_at)} readOnly/></label>
        </div>

        <div className="admin-user-editor-derived" aria-label="Calculated financial values">
          <div><small>Invested</small><b>{formatMoney(displayUser.invested_minor,displayUser.balance_asset_code)}</b></div>
          <div><small>Referrals</small><b>{formatMoney(displayUser.referral_minor,displayUser.balance_asset_code)}</b></div>
          <div><small>Portfolio</small><b>{formatMoney(displayUser.portfolio_minor,displayUser.balance_asset_code)}</b></div>
        </div>

        <div className="admin-user-editor-finances">
          <label><span><Wallet size={14}/> Wallet balance target ({user.balance_asset_code})</span><input required type="number" min="0" step="0.01" value={values.wallet_target} disabled={currencyChanged} onChange={event=>update('wallet_target',event.target.value)}/></label>
          <label><span><Coins size={14}/> Received bonus ({user.balance_asset_code})</span><input required type="number" min="0" step="0.01" value={values.bonus_target} disabled={currencyChanged} onChange={event=>update('bonus_target',event.target.value)}/></label>
          <label><span><TrendingUp size={14}/> Invested total target ({user.balance_asset_code})</span><input type="number" min="0" step="0.01" value={investedTarget} disabled={saving||currencyChanged} onChange={event=>setInvestedTarget(event.target.value)}/></label>
        </div>
        <p className="admin-user-editor-note">Portfolio is calculated from wallet balance and invested total, then refreshed after each saved action. Wallet changes use the ledger; an invested-total adjustment is audited but does not create an ROI-earning investment.</p>
        {currencyChanged&&<p className="admin-user-editor-note">Save the country change first, then reopen to edit the new local-currency balance. Existing balances stay in their original currency; no exchange conversion is applied.</p>}
        {investedError&&<div className="admin-user-editor-error" role="alert">{investedError}</div>}
        {summaryError&&<div className="admin-user-editor-error" role="alert">{summaryError}</div>}
        {error&&<div className="admin-user-editor-error" role="alert">{error}</div>}
        <footer className="admin-user-editor-actions">
          <button type="button" className="outline-button" disabled={saving||investmentActionBusy} onClick={onClose}>Cancel</button>
          <button type="button" className="outline-button" disabled={saving||investmentActionBusy||currencyChanged} onClick={updateInvested}>Update invested total</button>
          <button type="submit" className="primary compact" disabled={saving||investmentActionBusy}><Check size={15}/>{saving?'Saving…':'Save changes'}</button>
        </footer>
      </form>
      <section className="admin-user-existing-investments" aria-labelledby="admin-user-existing-investments-title">
        <header className="admin-user-existing-investments-header">
          <div><h3 id="admin-user-existing-investments-title">Existing investments</h3><p>Edit an investment amount or cancel it while preserving its financial history.</p></div>
          <button type="button" className="text-button" disabled={investmentsLoading} onClick={()=>void loadUserInvestments()}>{investmentsLoading?'Refreshing…':'Refresh'}</button>
        </header>
        {investmentsError&&<div className="admin-user-editor-error" role="alert">{investmentsError}</div>}
        {investmentsLoading&&!userInvestments.rows.length&&<p className="admin-user-investments-empty">Loading investments…</p>}
        {!investmentsLoading&&!investmentsError&&!userInvestments.rows.length&&<p className="admin-user-investments-empty">This member has no investments yet.</p>}
        <div className="admin-user-investments-list">
          {userInvestments.rows.map(investment=><article className="admin-user-investment-card" key={investment.id}>
            <div className="admin-user-investment-overview">
              <div><b>{investment.plan}</b><small>{investment.id.slice(0,8)} · {formatDate(investment.date)}</small></div>
              <div><strong>{formatMoney(investment.principal_minor,investment.asset_code)}</strong><span className={`status-tag ${investment.status==='cancelled'?'muted':''}`}>{investment.status}</span></div>
            </div>
            {investment.creation_source==='admin'&&<small className="admin-user-investment-source">{investment.admin_funding_method==='no_wallet_debit'?'Admin-created · no wallet debit':'Admin-created · wallet funded'}</small>}
            {investmentAction?.id===investment.id
              ?<form className="admin-user-investment-action-form" onSubmit={submitInvestmentAction}>
                {investmentAction.mode==='edit'
                  ?<><label><span>New amount ({investment.asset_code})</span><input required type="number" min="0" step="0.01" value={investmentActionAmount} onChange={event=>setInvestmentActionAmount(event.target.value)}/></label>{zeroInvestmentAmount&&<p className="admin-user-editor-note">Zero cancels the investment, stops future returns, and removes it from the active portfolio. Any verified wallet-funded amount is handled through the ledger.</p>}</>
                  :<p className="admin-user-editor-note">{investment.status==='pending'
                    ?'The pending investment and payment proof will be cancelled; no wallet refund is issued.'
                    :(investment.creation_source==='admin'&&investment.admin_funding_method==='no_wallet_debit'
                      ?'This stops future returns. No refund is issued because this investment did not debit the wallet.'
                      :'This stops future returns and refunds the verified wallet-funded principal. Previously credited returns are retained.')}</p>}
                <label><span>Audit note (optional)</span><input maxLength={500} value={investmentActionReason} onChange={event=>setInvestmentActionReason(event.target.value)} placeholder="Optional note; admin and action are recorded automatically"/></label>
                {investmentActionError&&<div className="admin-user-editor-error" role="alert">{investmentActionError}</div>}
                <div className="admin-user-investment-actions">
                  <button type="button" className="outline-button" disabled={investmentActionBusy} onClick={()=>{setInvestmentAction(null);setInvestmentActionError('')}}>Keep investment</button>
                  <button type="submit" className={investmentActionCancelling?'admin-investment-danger':'primary'} disabled={investmentActionBusy||saving}>{investmentActionBusy?(investmentActionCancelling?'Cancelling…':'Saving…'):investmentActionCancelling?'Cancel investment':'Save amount'}</button>
                </div>
              </form>
              :<div className="admin-user-investment-actions">
                {['active','completed'].includes(investment.status)&&<button type="button" className="text-button" disabled={saving||currencyChanged} onClick={()=>startInvestmentAction(investment,'edit')}><TrendingUp size={14}/> Edit amount</button>}
                {['pending','active','completed'].includes(investment.status)&&<button type="button" className="text-button admin-investment-cancel-link" disabled={saving||currencyChanged} onClick={()=>startInvestmentAction(investment,'cancel')}>Cancel</button>}
              </div>}
          </article>)}
        </div>
        {userInvestments.total>investmentPageSize&&<div className="admin-user-investments-pagination"><span>Page {investmentPage} of {investmentTotalPages}</span><div><button type="button" disabled={investmentPage<=1||investmentsLoading} onClick={()=>setInvestmentPage(page=>page-1)}><ChevronLeft size={14}/> Previous</button><button type="button" disabled={investmentPage>=investmentTotalPages||investmentsLoading} onClick={()=>setInvestmentPage(page=>page+1)}>Next <ChevronRight size={14}/></button></div></div>}
      </section>
      <form className="admin-user-editor-investment" onSubmit={submitInvestment}>
        <div>
          <h3>Create an investment</h3>
          <p>The plan sets the currency and return terms. Admins can set any positive amount without debiting the member's wallet.</p>
        </div>
        <div className="admin-user-editor-investment-fields">
          <label><span>Plan</span><select required value={investmentPlanId} disabled={saving||investmentActionBusy||plansLoading||currencyChanged||!availablePlans.length} onChange={event=>{const plan=availablePlans.find(row=>row.id===event.target.value);setInvestmentPlanId(event.target.value);setInvestmentAmount(plan?(Number(plan.minimum_minor||0)/100).toFixed(2):'');setInvestmentRequestId(crypto.randomUUID())}}>
            <option value="">{plansLoading?'Loading plans…':'Choose a plan'}</option>
            {availablePlans.map(plan=><option key={plan.id} value={plan.id}>{plan.name} · {plan.settlement_asset_code}</option>)}
          </select></label>
          <label><span>Amount{selectedPlan?` (${selectedPlan.settlement_asset_code})`:''}</span><input required type="number" min="0.01" step="0.01" value={investmentAmount} disabled={saving||investmentActionBusy||plansLoading||currencyChanged||!selectedPlan} onChange={event=>{setInvestmentAmount(event.target.value);setInvestmentRequestId(crypto.randomUUID())}}/></label>
        </div>
        {(plansError||!plansLoading&&!availablePlans.length)&&<p className="admin-user-editor-note">{plansError||"No active investment plans are available for this member's country."}</p>}
        {currencyChanged&&<p className="admin-user-editor-note">Save the country change before creating an investment for the new country.</p>}
        {investmentError&&<div className="admin-user-editor-error" role="alert">{investmentError}</div>}
        <div className="admin-user-editor-investment-actions"><button type="submit" className="outline-button" disabled={saving||investmentActionBusy||plansLoading||currencyChanged||!selectedPlan}><TrendingUp size={15}/>{saving?'Creating…':'Create investment'}</button></div>
      </form>
    </section>
  </div>;
}
