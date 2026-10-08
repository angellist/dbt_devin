{% set finished_statuses = var('devin__finished_statuses', ['exit', 'error']) %}

with sessions as (
    select *
    from {{ ref('stg_devin__sessions') }}
),

tags as (
    select
        sessions.session_id,
        array_agg(session_tag.value::varchar) within group (order by session_tag.value::varchar) as tag_list
    from sessions,
        lateral flatten(input => sessions.tags, outer => true) as session_tag
    where session_tag.value is not null
    group by 1
),

pull_requests as (
    select
        sessions.session_id,
        count(*) as pull_request_count,
        count_if(pr.value:pr_state::varchar = 'merged') as merged_pull_request_count
    from sessions,
        lateral flatten(input => sessions.pull_requests) as pr
    group by 1
)

select
    sessions.session_id,
    {% if var('devin__include_session_title', false) %}
    sessions.session_title,
    {% endif %}
    sessions.session_status,
    sessions.session_status_detail,
    sessions.created_at,
    sessions.updated_at,
    sessions.acus_consumed,
    sessions.org_id,
    sessions.user_id,
    sessions.service_user_id,
    sessions.origin,
    sessions.category,
    sessions.subcategory,
    sessions.devin_mode,
    sessions.playbook_id,
    sessions.automation_id,
    sessions.parent_session_id,
    sessions.is_archived,
    sessions.session_url,
    sessions.created_at::date as created_date,
    date_trunc('week', sessions.created_at)::date as created_week,
    date_trunc('month', sessions.created_at)::date as created_month,
    coalesce(tags.tag_list, array_construct()) as tag_list,
    coalesce(pull_requests.pull_request_count, 0) as pull_request_count,
    coalesce(pull_requests.merged_pull_request_count, 0) as merged_pull_request_count,
    sessions.service_user_id is not null as is_service_user_session,
    sessions.parent_session_id is not null as is_child_session,
    sessions.session_status in (
        {%- for status in finished_statuses %}
        '{{ status }}'{{ ',' if not loop.last }}
        {%- endfor %}
    ) as is_finished,
    sessions.loaded_at
from sessions
left join tags
    on sessions.session_id = tags.session_id
left join pull_requests
    on sessions.session_id = pull_requests.session_id
