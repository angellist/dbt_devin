with sessions as (
    select *
    from {{ ref('stg_devin__sessions') }}
),

-- One row per (session, PR URL). The same PR can be touched by more than one
-- session (e.g. a parent and its child), so pr_url alone is not the grain.
session_pull_requests as (
    select
        sessions.session_id,
        pr.value:pr_url::varchar as pr_url,
        pr.value:pr_state::varchar as pr_state
    from sessions,
        lateral flatten(input => sessions.pull_requests) as pr
    where pr.value:pr_url is not null
    qualify
        row_number() over (
            partition by sessions.session_id, pr.value:pr_url::varchar order by pr.index desc
        ) = 1
)

select
    md5(session_pull_requests.session_id || '|' || session_pull_requests.pr_url) as session_pull_request_id,
    session_pull_requests.session_id,
    session_pull_requests.pr_url,
    session_pull_requests.pr_state,
    session_pull_requests.pr_state = 'merged' as is_merged,
    regexp_substr(session_pull_requests.pr_url, 'github\\.com/([^/]+)/([^/]+)/pull/([0-9]+)', 1, 1, 'e', 1)
        as github_repo_owner,
    regexp_substr(session_pull_requests.pr_url, 'github\\.com/([^/]+)/([^/]+)/pull/([0-9]+)', 1, 1, 'e', 2)
        as github_repo_name,
    regexp_substr(session_pull_requests.pr_url, 'github\\.com/([^/]+)/([^/]+)/pull/([0-9]+)', 1, 1, 'e', 3)::number
        as github_pr_number,
    sessions.org_id,
    sessions.user_id,
    sessions.service_user_id,
    sessions.origin as session_origin,
    sessions.session_status,
    sessions.created_at as session_created_at,
    sessions.updated_at as session_updated_at,
    sessions.loaded_at
from session_pull_requests
inner join sessions
    on session_pull_requests.session_id = sessions.session_id
