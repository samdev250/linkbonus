insert into public.admin_roles (user_id, role, permissions)
select p.id, 'super_admin', array['*']::text[]
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) = lower('infolinkbonusinvest@gmail.com')
on conflict (user_id) do update
  set role = excluded.role,
      permissions = excluded.permissions;
