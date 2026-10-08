{{ config(enabled=var('devin__using_roles', true)) }}

with source as (
    select
        data,
        {{ devin_loaded_at() }} as loaded_at
    from {{ source('devin', 'roles') }}
),

deduped as (
    select *
    from source
    qualify
        row_number() over (
            partition by data:role_id order by loaded_at desc
        ) = 1
)

select
    data:role_id::varchar as role_id,
    data:role_name::varchar as role_name,
    data:role_type::varchar as role_type,
    data:org_id::varchar as org_id,
    loaded_at
from deduped
