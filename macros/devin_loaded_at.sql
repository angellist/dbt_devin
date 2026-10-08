{#
  Name of the load-timestamp column on the landing tables. Defaults to
  `loaded_at`; set `devin_loaded_at_column` when your loader uses another name
  (for example `airflow_loaded_at`).
#}
{% macro devin_loaded_at() -%}
    {{ var('devin_loaded_at_column', 'loaded_at') }}
{%- endmacro %}
