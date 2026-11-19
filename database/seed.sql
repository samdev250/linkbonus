-- Draft plan catalog only. Amounts are illustrative USD minor units; plans remain inactive.
insert into public.investment_plans(name,minimum_minor,maximum_minor,active)
values ('Starter',1000,1000,false),('Basic',2500,2500,false),('Silver',5000,5000,false),
('Bronze',10000,10000,false),('Gold',25000,25000,false),('Platinum',50000,50000,false),
('Diamond',100000,100000,false),('Premium',250000,250000,false),
('Professional',500000,500000,false),('VIP',1000000,1000000,false)
on conflict(name) do nothing;
