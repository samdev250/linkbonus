-- Remove the legacy risk-disclosure wording from all published plans.
update public.investment_plans
set risk_disclosure = '', updated_at = now()
where risk_disclosure ilike '%Capital at risk%'
   or risk_disclosure ilike '%not guaranteed%';
