{% set acu_cost_usd = var('devin_acu_cost_usd', none) %}

with sessions as (
    select *
    from {{ ref('fct_devin_sessions') }}
)

-- Daily rollup of fct_devin_sessions keyed on the session's creation date, so
-- a session's ACUs land on the day it started even if it ran longer. Only
-- dates with at least one session appear; spine against your date dimension
-- if you need dense dates.
select
    created_date,
    org_id,
    user_id,
    service_user_id,
    origin,
    count(*) as session_count,
    count_if(is_finished) as finished_session_count,
    count_if(is_child_session) as child_session_count,
    sum(acus_consumed) as acus_consumed,
    {% if acu_cost_usd is not none %}
    sum(acus_consumed) * {{ acu_cost_usd }} as acu_cost_usd,
    {% endif %}
    sum(pull_request_count) as pull_request_count,
    sum(merged_pull_request_count) as merged_pull_request_count,
    max(loaded_at) as loaded_at
from sessions
group by 1, 2, 3, 4, 5
