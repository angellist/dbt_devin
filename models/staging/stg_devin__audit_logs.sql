{{ config(enabled=var('devin__using_audit_logs', true)) }}

with source as (
    select
        data,
        {{ devin_loaded_at() }} as loaded_at
    from {{ source('devin', 'audit_logs') }}
),

deduped as (
    select *
    from source
    qualify
        row_number() over (
            partition by data:audit_log_id order by loaded_at
        ) = 1
)

select
    data:audit_log_id::varchar as audit_log_id,
    data:action::varchar as action,
    to_timestamp(data:created_at::number) as created_at,
    data:org_id::varchar as org_id,
    data:user_id::varchar as actor_user_id,
    data:user_email::varchar as actor_user_email,
    data:service_user_id::varchar as actor_service_user_id,
    data:service_user_name::varchar as actor_service_user_name,
    data:data:target_user_id::varchar as target_user_id,
    data:data:roles as role_ids,
    data:data as event_data,
    loaded_at
from deduped
