{{ config(enabled=var('devin__using_org_members', true)) }}

with source as (
    select
        data,
        {{ devin_loaded_at() }} as loaded_at
    from {{ source('devin', 'org_members') }}
)

select
    data:user_id::varchar as user_id,
    data:org_id::varchar as org_id,
    data:org_name::varchar as org_name,
    data:email::varchar as org_member_email,
    data:name::varchar as org_member_name,
    data:role_assignments as role_assignments,
    loaded_at as snapshot_at
from source
