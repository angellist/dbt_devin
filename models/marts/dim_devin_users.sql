{% set using_members = var('devin__using_org_members', true) %}

with sessions as (
    select *
    from {{ ref('fct_devin_sessions') }}
    where user_id is not null
),

session_activity as (
    select
        user_id,
        count(*) as session_count,
        count_if(created_at >= dateadd('day', -30, current_timestamp())) as session_count_last_30d,
        sum(acus_consumed) as acus_consumed,
        min(created_at) as first_session_at,
        max(created_at) as last_session_at
    from sessions
    group by 1
),

{% if using_members %}
-- `devin-export members` walks every organization in one run, so the newest
-- snapshot_at is the latest full export and defines who is currently a member.
latest_snapshot as (
    select max(snapshot_at) as snapshot_at
    from {{ ref('stg_devin__org_members') }}
),

current_memberships as (
    select members.*
    from {{ ref('stg_devin__org_members') }} as members
    inner join latest_snapshot
        on members.snapshot_at = latest_snapshot.snapshot_at
),

current_members as (
    select
        user_id,
        max(org_member_email) as user_email,
        max(org_member_name) as user_full_name,
        count(distinct org_id) as org_count,
        array_agg(distinct org_id) within group (order by org_id) as org_ids,
        min(snapshot_at) as member_as_of
    from current_memberships
    group by 1
),

membership_roles as (
    select
        current_memberships.user_id,
        role_assignment.value:role:role_name::varchar as role_name
    from current_memberships,
        lateral flatten(input => current_memberships.role_assignments) as role_assignment
    where role_assignment.value:role:role_name is not null
),

current_role_names as (
    select
        user_id,
        array_agg(distinct role_name) within group (order by role_name) as role_names
    from membership_roles
    group by 1
),

-- Users who have sessions but are absent from the latest export (removed
-- seats) still get a row, with attributes from their last-known snapshot.
last_known_attributes as (
    select
        user_id,
        org_member_email as user_email,
        org_member_name as user_full_name
    from {{ ref('stg_devin__org_members') }}
    qualify
        row_number() over (
            partition by user_id order by snapshot_at desc
        ) = 1
),

users as (
    select user_id from current_members
    union distinct
    select user_id from session_activity
),
{% else %}
users as (
    select user_id from session_activity
),
{% endif %}

final as (
    select
        users.user_id,
        {% if using_members %}
        coalesce(current_members.user_email, last_known_attributes.user_email) as user_email,
        coalesce(current_members.user_full_name, last_known_attributes.user_full_name) as user_full_name,
        current_members.user_id is not null as is_current_member,
        coalesce(current_members.org_count, 0) as org_count,
        coalesce(current_members.org_ids, array_construct()) as org_ids,
        coalesce(current_role_names.role_names, array_construct()) as role_names,
        current_members.member_as_of,
        {% else %}
        cast(null as varchar) as user_email,
        cast(null as varchar) as user_full_name,
        cast(null as boolean) as is_current_member,
        cast(null as number) as org_count,
        cast(null as array) as org_ids,
        cast(null as array) as role_names,
        cast(null as timestamp_ntz) as member_as_of,
        {% endif %}
        coalesce(session_activity.session_count, 0) as session_count,
        coalesce(session_activity.session_count_last_30d, 0) as session_count_last_30d,
        coalesce(session_activity.acus_consumed, 0) as acus_consumed,
        session_activity.first_session_at,
        session_activity.last_session_at,
        session_activity.session_count_last_30d > 0 as is_active_last_30d
    from users
    left join session_activity
        on users.user_id = session_activity.user_id
    {% if using_members %}
    left join current_members
        on users.user_id = current_members.user_id
    left join current_role_names
        on users.user_id = current_role_names.user_id
    left join last_known_attributes
        on users.user_id = last_known_attributes.user_id
    {% endif %}
)

select *
from final
