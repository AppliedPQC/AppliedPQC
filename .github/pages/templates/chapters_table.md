
## Every listing in the book

All {{ n_listings }} code listings from the chapters, runnable the same way.
Each cell replays its chapter's earlier listings first, so any snippet can be
tried on its own.

| Chapter | Listings | |
| --- | --- | --- |
{% for c in chapters -%}
| {{ c.title }} | {{ c.listings|length }} | [run](playground-{{ c.stem }}.html) |
{% endfor %}
