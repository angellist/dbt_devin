{{ config(enabled=var('devin__using_organizations', true)) }}

{% set using_members = var('devin__using_org_members', true) %}

with organizations as (
    select *
    from {{ ref('stg_devin__organizations') }}
),

{% if using_members %}
latest_snapshot as (
    select
        org_id,
        max(snapshot_at) as snapshot_at
    from {{ ref('stg_devin__org_members') }}
    group by 1
),

member_counts as (
    select
        members.org_id,
        latest_snapshot.snapshot_at as members_as_of,
        count(distinct members.user_id) as member_count
    from {{ ref('stg_devin__org_members') }} as members
    inner join latest_snapshot
        on
            members.org_id = latest_snapshot.org_id
            and members.snapshot_at = latest_snapshot.snapshot_at
    group by 1, 2
),
{% endif %}

final as (
    select
        organizations.org_id,
        organizations.org_name,
        {% if using_members %}
        member_counts.member_count,
        member_counts.members_as_of,
        {% else %}
        cast(null as number) as member_count,
        cast(null as timestamp_ntz) as members_as_of,
        {% endif %}
        organizations.loaded_at
    from organizations
    {% if using_members %}
    left join member_counts
        on organizations.org_id = member_counts.org_id
    {% endif %}
)

select *
from final
