-- Publish the Burundi plan tiers alongside the Rwandan catalogue.
insert into public.investment_plans (name, minimum_minor, maximum_minor, roi_rate_bps, roi_interval_hours, duration_days, active, settlement_asset_code, performance_methodology, risk_disclosure, updated_at)
values
  ('BIF 100,000',     10000000,   null, 500, 24, 30, true, 'BIF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('BIF 200,000',     20000000,   null, 500, 24, 30, true, 'BIF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('BIF 300,000',     30000000,   null, 500, 24, 30, true, 'BIF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('BIF 400,000',     40000000,   null, 500, 24, 30, true, 'BIF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('BIF 500,000',     50000000,   null, 500, 24, 30, true, 'BIF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('BIF 600,000',     60000000,   null, 500, 24, 30, true, 'BIF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('BIF 700,000',     70000000,   null, 500, 24, 30, true, 'BIF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('BIF 800,000',     80000000,   null, 500, 24, 30, true, 'BIF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('BIF 900,000',     90000000,   null, 500, 24, 30, true, 'BIF', '5% daily income calculated from your active principal every 24 hours.', '', now()),
  ('BIF 1,000,000',  100000000,   null, 500, 24, 30, true, 'BIF', '5% daily income calculated from your active principal every 24 hours.', '', now())
on conflict (name) do update set
  minimum_minor = excluded.minimum_minor,
  maximum_minor = excluded.maximum_minor,
  roi_rate_bps = excluded.roi_rate_bps,
  roi_interval_hours = excluded.roi_interval_hours,
  duration_days = excluded.duration_days,
  active = true,
  settlement_asset_code = 'BIF',
  performance_methodology = excluded.performance_methodology,
  risk_disclosure = excluded.risk_disclosure,
  updated_at = now();
