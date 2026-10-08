{{ config(enabled=var('devin__using_audit_logs', true)) }}

with audit_logs as (
    select *
    from {{ ref('stg_devin__audit_logs') }}
),

membership_events as (
    select
        audit_log_id,
        action,
        created_at,
        org_id,
        actor_user_id,
        actor_user_email,
        actor_service_user_id,
        actor_service_user_name,
        target_user_id,
        role_ids
    from audit_logs
    where action in ('add_member', 'delete_member')
),

{% if var('devin__using_org_members', true) %}
-- Latest known attributes per user across all snapshots, so removed users
-- (absent from the live member list) still resolve to a name and email.
latest_user_attributes as (
    select
        user_id,
        org_member_email,
        org_member_name
    from {{ ref('stg_devin__org_members') }}
    qualify
        row_number() over (
            partition by user_id order by snapshot_at desc
        ) = 1
),
{% endif %}

{% if var('devin__using_organizations', true) %}
org_names as (
    select
        org_id,
        org_name
    from {{ ref('stg_devin__organizations') }}
),
{% elif var('devin__using_org_members', true) %}
org_names as (
    select
        org_id,
        org_name
    from {{ ref('stg_devin__org_members') }}
    qualify
        row_number() over (
            partition by org_id order by snapshot_at desc
        ) = 1
),
{% endif %}

{% if var('devin__using_roles', true) %}
event_role_ids as (
    select
        membership_events.audit_log_id,
        role_id.value::varchar as role_id
    from membership_events,
        lateral flatten(input => membership_events.role_ids) as role_id
),

event_roles as (
    select
        event_role_ids.audit_log_id,
        coalesce(roles.role_name, event_role_ids.role_id) as role_label
    from event_role_ids
    left join {{ ref('stg_devin__roles') }} as roles
        on event_role_ids.role_id = roles.role_id
),

role_names as (
    select
        audit_log_id,
        array_agg(role_label) within group (order by role_label) as role_names
    from event_roles
    group by 1
),
{% endif %}

final as (
    select
        membership_events.audit_log_id,
        membership_events.created_at as changed_at,
        case membership_events.action
            when 'add_member' then 'added'
            when 'delete_member' then 'removed'
        end as change_type,
        membership_events.org_id,
        {% if var('devin__using_organizations', true) or var('devin__using_org_members', true) %}
        org_names.org_name,
        {% else %}
        cast(null as varchar) as org_name,
        {% endif %}
        membership_events.target_user_id,
        {% if var('devin__using_org_members', true) %}
        latest_user_attributes.org_member_email as target_user_email,
        latest_user_attributes.org_member_name as target_user_name,
        {% else %}
        cast(null as varchar) as target_user_email,
        cast(null as varchar) as target_user_name,
        {% endif %}
        membership_events.actor_user_id,
        membership_events.actor_user_email,
        membership_events.actor_service_user_id,
        membership_events.actor_service_user_name,
        membership_events.role_ids,
        {% if var('devin__using_roles', true) %}
        role_names.role_names
        {% else %}
        cast(null as array) as role_names
        {% endif %}
    from membership_events
    {% if var('devin__using_org_members', true) %}
    left join latest_user_attributes
        on membership_events.target_user_id = latest_user_attributes.user_id
    {% endif %}
    {% if var('devin__using_organizations', true) or var('devin__using_org_members', true) %}
    left join org_names
        on membership_events.org_id = org_names.org_id
    {% endif %}
    {% if var('devin__using_roles', true) %}
    left join role_names
        on membership_events.audit_log_id = role_names.audit_log_id
    {% endif %}
)

select *
from final
