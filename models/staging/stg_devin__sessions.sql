with source as (
    select
        data,
        {{ devin_loaded_at() }} as loaded_at
    from {{ source('devin', 'sessions') }}
),

deduped as (
    select *
    from source
    qualify
        row_number() over (
            partition by data:session_id order by loaded_at desc, data:updated_at desc
        ) = 1
)

select
    data:session_id::varchar as session_id,
    data:title::varchar as session_title,
    data:status::varchar as session_status,
    data:status_detail::varchar as session_status_detail,
    data:acus_consumed::float as acus_consumed,
    data:org_id::varchar as org_id,
    data:user_id::varchar as user_id,
    data:service_user_id::varchar as service_user_id,
    data:origin::varchar as origin,
    data:category::varchar as category,
    data:subcategory::varchar as subcategory,
    data:devin_mode::varchar as devin_mode,
    data:playbook_id::varchar as playbook_id,
    data:automation_id::varchar as automation_id,
    data:parent_session_id::varchar as parent_session_id,
    data:is_archived::boolean as is_archived,
    data:url::varchar as session_url,
    to_timestamp(data:created_at::number) as created_at,
    to_timestamp(data:updated_at::number) as updated_at,
    data:tags as tags,
    data:pull_requests as pull_requests,
    loaded_at
from deduped
