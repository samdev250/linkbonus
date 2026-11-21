update public.investment_plans
set roi_rate_bps = 500,
    roi_interval_hours = 24,
    performance_methodology = '5% daily income calculated from your active principal every 24 hours.',
    risk_disclosure = '',
    updated_at = now()
where active = true;

update public.investments
set roi_rate_bps = 500,
    roi_interval_hours = 24,
    updated_at = now()
where status = 'active' and roi_rate_bps > 0;
