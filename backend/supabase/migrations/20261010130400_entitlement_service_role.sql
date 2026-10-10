-- P1-10 KIDS-08. Parents can read an entitlement. They cannot grant one.
-- Writes go through grant_entitlement, which only the service role may call
-- after the App Store Server API JWS has been verified.

drop policy if exists entitlement_insert on public.entitlement;
drop policy if exists entitlement_update on public.entitlement;
drop policy if exists entitlement_delete on public.entitlement;

revoke insert, update, delete on table public.entitlement from authenticated;

create or replace function public.grant_entitlement(
  parent uuid,
  product text,
  entitlement_status text,
  expires timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.entitlement (parent_id, storekit_product, status, expires_at)
  values (parent, product, entitlement_status, expires)
  on conflict (parent_id, storekit_product)
  do update set
    status = excluded.status,
    expires_at = excluded.expires_at,
    updated_at = now();
end;
$$;

revoke all on function public.grant_entitlement(uuid, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.grant_entitlement(uuid, text, text, timestamptz) to service_role;
