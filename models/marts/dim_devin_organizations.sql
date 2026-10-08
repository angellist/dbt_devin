{{ config(enabled=var('devin__using_organizations', true)) }}

{% set using_members = var('devin__using_org_members', true) %}

with organizations as (
    select *
    from {{ ref('stg_devin__organizations') }}
),

{% if using_members %}
-- `devin-export members` walks every organization in one run, so the newest
-- snapshot_at across all orgs is the latest full export. Orgs with no rows in
-- that export have zero members rather than a stale count.
latest_snapshot as (
    select max(snapshot_at) as snapshot_at
    from {{ ref('stg_devin__org_members') }}
),

member_counts as (
    select
        members.org_id,
        count(distinct members.user_id) as member_count
    from {{ ref('stg_devin__org_members') }} as members
    inner join latest_snapshot
        on members.snapshot_at = latest_snapshot.snapshot_at
    group by 1
),
{% endif %}

final as (
    select
        organizations.org_id,
        organizations.org_name,
        {% if using_members %}
        coalesce(member_counts.member_count, 0) as member_count,
        latest_snapshot.snapshot_at as members_as_of,
        {% else %}
        cast(null as number) as member_count,
        cast(null as timestamp_ntz) as members_as_of,
        {% endif %}
        organizations.loaded_at
    from organizations
    {% if using_members %}
    cross join latest_snapshot
    left join member_counts
        on organizations.org_id = member_counts.org_id
    {% endif %}
)

select *
from final
