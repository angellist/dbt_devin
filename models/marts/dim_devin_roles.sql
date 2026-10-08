{{ config(enabled=var('devin__using_roles', true)) }}

with roles as (
    select *
    from {{ ref('stg_devin__roles') }}
),

{% if var('devin__using_organizations', true) %}
organizations as (
    select
        org_id,
        org_name
    from {{ ref('stg_devin__organizations') }}
),
{% endif %}

final as (
    select
        roles.role_id,
        roles.role_name,
        roles.role_type,
        roles.org_id,
        {% if var('devin__using_organizations', true) %}
        organizations.org_name,
        {% else %}
        cast(null as varchar) as org_name,
        {% endif %}
        roles.loaded_at
    from roles
    {% if var('devin__using_organizations', true) %}
    left join organizations
        on roles.org_id = organizations.org_id
    {% endif %}
)

select *
from final
