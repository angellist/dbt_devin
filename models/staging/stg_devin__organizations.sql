{{ config(enabled=var('devin__using_organizations', true)) }}

with source as (
    select
        data,
        {{ devin_loaded_at() }} as loaded_at
    from {{ source('devin', 'organizations') }}
),

deduped as (
    select *
    from source
    qualify
        row_number() over (
            partition by data:org_id order by loaded_at desc
        ) = 1
)

select
    data:org_id::varchar as org_id,
    data:name::varchar as org_name,
    loaded_at
from deduped
