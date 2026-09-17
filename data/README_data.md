# data/

This folder holds the static corpus and database schema used by the menu bar app and the local web view. Every quote is verbatim from a public-domain text. Run `python3 scripts/verify_quotes.py` to re-check the quotes against the source texts. The script needs the local `source/` folder, which is not included in the repo.

| File | Contents |
|---|---|
| `quotes.json` | The quote corpus: an array of quote objects (see below). |
| `quotes.md` | The same corpus as a Markdown table: `Quote \| Author \| Source Work \| Relevance`. |
| `teachings.md` | The corpus grouped by theme. Each theme has a short synthesis, its quotes, and cross-references by id. |
| `corpus_meta.json` | The author → works index with quote counts, including works that have no quotes. |
| `schema.sql` | The SQLite schema: corpus tables, pins and tags, daily logs, pin-count views, and the recommendation query (in comments). |

## `quotes.json`

```json
[
  {
    "id": "q0001",
    "quote": "Verbatim passage (whitespace collapsed).",
    "author": "Epictetus",
    "work": "Enchiridion",
    "source_file": "source/02_Epictetus_Discourses.md",
    "themes": ["agency", "judgment"],
    "relevance": "One generic sentence on how the passage breaks a fear-driven feedback loop."
  }
]
```

- `id` is `q` plus four digits, unique, and ordered by source file and then by position in the text.
- `themes` come from a fixed vocabulary: `agency`, `will`, `courage`, `fear`, `attention`, `judgment`, `detachment`, `indifference`, `presence`, `action`, `self-mastery`, `freedom`, `suffering`, `fate`. The first theme is the primary one.
- `work` names the actual work. Some source files hold more than one (several stories, a selection of writings, or an appendix), so several works can share one `source_file`.
- Verbatim rule: after collapsing whitespace, removing `_` emphasis marks and numeric footnote markers like `[12]`, and folding curly quotes and dashes to straight ones on both sides, each `quote` is an exact substring of its `source_file`.

## `corpus_meta.json`

```json
{
  "authors": [
    {
      "name": "Søren Kierkegaard",
      "works": [
        { "title": "Fear and Trembling", "source_file": "source/16_Kierkegaard_Selections.md", "quote_count": 15 }
      ]
    }
  ]
}
```

Authors appear in corpus order. `quote_count` can be `0`. Seed `authors` and `works` from this file, then load `quotes` from `quotes.json` by matching (`author`, `work`).

## `schema.sql`

- **Corpus:** `authors`, `works`, `quotes` (`themes` holds a JSON array stored as text).
- **Pins:** `user_pins` allows one pin per quote. `tags` and `pin_tags` are many-to-many and cascade on delete.
- **Tracker:** `daily_logs` has one row per `YYYY-MM-DD` date. `mood`, `sleep`, `strength` and `stillness` are each 1–9. Composite = mood×1 + sleep×1 + strength×2 + stillness×2.
- **Views:** `v_author_pin_counts` and `v_work_pin_counts`. Both include rows with zero pins.
- **Recommendations:** for each author with at least one pin, ordered by pin count (highest first), every unpinned work becomes a poster `{author, work, author_pin_count, teaser_quote}`. The teaser is the quote with the lowest id in that work. The full query is in the comments at the end of `schema.sql`.
