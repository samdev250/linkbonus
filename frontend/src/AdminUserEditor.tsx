import {useEffect,useState,type FormEvent} from 'react';
import {Check,Coins,TrendingUp,Wallet,X} from 'lucide-react';
import countryToCurrency from 'country-to-currency';
import {CountrySelect} from './CountrySelect';

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

type Props = {
  user:User;
  saving:boolean;
  plans:any[];
  plansLoading:boolean;
  plansError:string;
  onClose:()=>void;
  onSave:(values:Values)=>Promise<void>;
  onCreateInvestment:(values:{plan_id:string;amount:string;request_id:string})=>Promise<void>;
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

export function AdminUserEditor({user,saving,plans,plansLoading,plansError,onClose,onSave,onCreateInvestment}:Props){
  const [values,setValues]=useState<Values>({
    full_name:user.name||'',
    country:user.country||'',
    phone:user.phone||'',
    status:user.status,
    verification_status:user.verification_status||'unverified',
    wallet_target:amountFromMinor(user.balance_minor),
    bonus_target:amountFromMinor(user.bonus_minor),
  });
  const [error,setError]=useState('');
  const [investmentPlanId,setInvestmentPlanId]=useState('');
  const [investmentAmount,setInvestmentAmount]=useState('');
  const [investmentRequestId,setInvestmentRequestId]=useState(()=>crypto.randomUUID());
  const [investmentError,setInvestmentError]=useState('');
  const availablePlans=plans.filter(plan=>plan.active&&(!plan.country_code||plan.country_code.toUpperCase()===String(user.country||'').toUpperCase()));
  const selectedPlan=availablePlans.find(plan=>plan.id===investmentPlanId);
  const currencyChanged=assetForCountry(values.country)!==user.balance_asset_code;

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
      if(event.key==='Escape'&&!saving)onClose();
    };
    window.addEventListener('keydown',closeOnEscape);
    return()=>window.removeEventListener('keydown',closeOnEscape);
  },[onClose,saving]);

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
    try{await onCreateInvestment({plan_id:investmentPlanId,amount:investmentAmount,request_id:investmentRequestId})}
    catch(reason){setInvestmentError(reason instanceof Error?reason.message:'Could not create this investment')}
  };

  return <div className="modal-backdrop admin-user-editor-backdrop" onClick={()=>!saving&&onClose()}>
    <section className="admin-user-editor" role="dialog" aria-modal="true" aria-labelledby="admin-user-editor-title" onClick={event=>event.stopPropagation()}>
      <header className="admin-user-editor-header">
        <div>
          <span className="eyebrow">MEMBER ACCOUNT</span>
          <h2 id="admin-user-editor-title">Update {user.name}</h2>
          <p>{user.email}</p>
        </div>
        <button type="button" className="icon-button" aria-label="Close update form" disabled={saving} onClick={onClose}><X size={18}/></button>
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
          <div><small>Invested</small><b>{formatMoney(user.invested_minor,user.balance_asset_code)}</b></div>
          <div><small>Referrals</small><b>{formatMoney(user.referral_minor,user.balance_asset_code)}</b></div>
          <div><small>Portfolio</small><b>{formatMoney(user.portfolio_minor,user.balance_asset_code)}</b></div>
        </div>

        <div className="admin-user-editor-finances">
          <label><span><Wallet size={14}/> Wallet balance ({user.balance_asset_code})</span><input required type="number" min="0" step="0.01" value={values.wallet_target} disabled={currencyChanged} onChange={event=>update('wallet_target',event.target.value)}/></label>
          <label><span><Coins size={14}/> Received bonus ({user.balance_asset_code})</span><input required type="number" min="0" step="0.01" value={values.bonus_target} disabled={currencyChanged} onChange={event=>update('bonus_target',event.target.value)}/></label>
        </div>
        {currencyChanged&&<p className="admin-user-editor-note">Save the country change first, then reopen to edit the new local-currency balance. Existing balances stay in their original currency; no exchange conversion is applied.</p>}
        {error&&<div className="admin-user-editor-error" role="alert">{error}</div>}
        <footer className="admin-user-editor-actions">
          <button type="button" className="outline-button" disabled={saving} onClick={onClose}>Cancel</button>
          <button type="submit" className="primary compact" disabled={saving}><Check size={15}/>{saving?'Saving…':'Save changes'}</button>
        </footer>
      </form>
      <form className="admin-user-editor-investment" onSubmit={submitInvestment}>
        <div>
          <h3>Create an investment</h3>
          <p>This creates a clearly admin-attributed investment, debits the member's existing wallet, and does not create a referral bonus.</p>
        </div>
        <div className="admin-user-editor-investment-fields">
          <label><span>Plan</span><select required value={investmentPlanId} disabled={saving||plansLoading||currencyChanged||!availablePlans.length} onChange={event=>{const plan=availablePlans.find(row=>row.id===event.target.value);setInvestmentPlanId(event.target.value);setInvestmentAmount(plan?(Number(plan.minimum_minor||0)/100).toFixed(2):'');setInvestmentRequestId(crypto.randomUUID())}}>
            <option value="">{plansLoading?'Loading plans…':'Choose a plan'}</option>
            {availablePlans.map(plan=><option key={plan.id} value={plan.id}>{plan.name} · {plan.settlement_asset_code} · min {Number(plan.minimum_minor||0)/100}</option>)}
          </select></label>
          <label><span>Amount{selectedPlan?` (${selectedPlan.settlement_asset_code})`:''}</span><input required type="number" min={selectedPlan?Number(selectedPlan.minimum_minor)/100:0.01} max={selectedPlan?.maximum_minor?Number(selectedPlan.maximum_minor)/100:undefined} step="0.01" value={investmentAmount} disabled={saving||plansLoading||currencyChanged||!selectedPlan} onChange={event=>{setInvestmentAmount(event.target.value);setInvestmentRequestId(crypto.randomUUID())}}/></label>
        </div>
        {(plansError||!plansLoading&&!availablePlans.length)&&<p className="admin-user-editor-note">{plansError||"No active investment plans are available for this member's country."}</p>}
        {currencyChanged&&<p className="admin-user-editor-note">Save the country change before creating an investment for the new country.</p>}
        {investmentError&&<div className="admin-user-editor-error" role="alert">{investmentError}</div>}
        <div className="admin-user-editor-investment-actions"><button type="submit" className="outline-button" disabled={saving||plansLoading||currencyChanged||!selectedPlan}><TrendingUp size={15}/>{saving?'Creating…':'Create investment'}</button></div>
      </form>
    </section>
  </div>;
}
