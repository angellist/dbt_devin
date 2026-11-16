{{ config(enabled=var('devin__using_roles', true)) }}

with roles as (
    select *
    from {{ ref('stg_devin__roles') }}
),

final as (
    select
        roles.role_id,
        roles.role_name,
        roles.role_type,
        roles.loaded_at
    from roles
)

select *
from final
