# Blog

Notes and research from the Applied PQC project.

{% for p in posts %}
## [{{ p.title }}](blog-{{ p.slug }}.html)

{{ p.date }}
{% if p.summary %}
{{ p.summary }}
{% endif %}
{% else %}
No posts yet.
{% endfor %}
