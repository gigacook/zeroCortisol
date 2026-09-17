-- zeroCortisol SQLite schema
-- Test:  sqlite3 :memory: < data/schema.sql
--
-- Seeding: authors / works / quotes are loaded from data/corpus_meta.json and
-- data/quotes.json. quotes.id keeps the JSON id ("q0001" ...), zero-padded, so
-- text ordering equals numeric ordering. quotes.themes stores the JSON array text.
-- user_pins, tags, pin_tags and daily_logs are user data written by the app.

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Corpus
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS authors (
    id    INTEGER PRIMARY KEY,
    name  TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS works (
    id         INTEGER PRIMARY KEY,
    author_id  INTEGER NOT NULL REFERENCES authors(id) ON DELETE CASCADE,
    title      TEXT NOT NULL,
    UNIQUE (author_id, title)
);

CREATE TABLE IF NOT EXISTS quotes (
    id         TEXT PRIMARY KEY CHECK (id GLOB 'q[0-9][0-9][0-9][0-9]*'),
    work_id    INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE,
    text       TEXT NOT NULL,
    relevance  TEXT NOT NULL,
    themes     TEXT NOT NULL DEFAULT '[]'  /* JSON array of theme strings */
);

-- ---------------------------------------------------------------------------
-- User pins and tags (user_pins_db)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_pins (
    id         INTEGER PRIMARY KEY,
    quote_id   TEXT NOT NULL UNIQUE REFERENCES quotes(id) ON DELETE CASCADE,
    pinned_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    note       TEXT
);

CREATE TABLE IF NOT EXISTS tags (
    id    INTEGER PRIMARY KEY,
    name  TEXT NOT NULL UNIQUE COLLATE NOCASE
);

CREATE TABLE IF NOT EXISTS pin_tags (
    pin_id  INTEGER NOT NULL REFERENCES user_pins(id) ON DELETE CASCADE,
    tag_id  INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (pin_id, tag_id)
);

-- ---------------------------------------------------------------------------
-- Daily tracker (daily_logs_db). One row per calendar day.
-- Composite score (computed in the app, not stored):
--   mood*1 + sleep*1 + strength*2 + stillness*2   (range 6..54)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_logs (
    date        TEXT PRIMARY KEY  /* YYYY-MM-DD */
                CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'),
    mood        INTEGER NOT NULL CHECK (mood      BETWEEN 1 AND 9),
    sleep       INTEGER NOT NULL CHECK (sleep     BETWEEN 1 AND 9),
    strength    INTEGER NOT NULL CHECK (strength  BETWEEN 1 AND 9),
    stillness   INTEGER NOT NULL CHECK (stillness BETWEEN 1 AND 9),
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_works_author      ON works(author_id);
CREATE INDEX IF NOT EXISTS idx_quotes_work       ON quotes(work_id, id);
CREATE INDEX IF NOT EXISTS idx_user_pins_pinned  ON user_pins(pinned_at);
CREATE INDEX IF NOT EXISTS idx_pin_tags_tag      ON pin_tags(tag_id);
-- daily_logs.date is the primary key, so range scans over dates are already indexed.

-- ---------------------------------------------------------------------------
-- Views: pin aggregation by author and by work (zero-pin rows included)
-- ---------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS v_author_pin_counts AS
SELECT a.id            AS author_id,
       a.name          AS author,
       COUNT(p.id)     AS pin_count
FROM authors a
LEFT JOIN works w     ON w.author_id = a.id
LEFT JOIN quotes q    ON q.work_id   = w.id
LEFT JOIN user_pins p ON p.quote_id  = q.id
GROUP BY a.id, a.name;

CREATE VIEW IF NOT EXISTS v_work_pin_counts AS
SELECT w.id            AS work_id,
       w.author_id     AS author_id,
       a.name          AS author,
       w.title         AS work,
       COUNT(p.id)     AS pin_count
FROM works w
JOIN authors a        ON a.id       = w.author_id
LEFT JOIN quotes q    ON q.work_id  = w.id
LEFT JOIN user_pins p ON p.quote_id = q.id
GROUP BY w.id, w.author_id, a.name, w.title;

-- ---------------------------------------------------------------------------
-- Recommendation engine ("Poster" format)
-- ---------------------------------------------------------------------------
-- Spec:
--   1. Aggregate pin counts per author (v_author_pin_counts) and per work
--      (v_work_pin_counts).
--   2. Consider only authors with at least one pin, ordered by author pin count
--      descending (ties: author name ascending).
--   3. For each such author, list every work of theirs that has zero pins
--      (ties within an author: work title ascending).
--   4. Emit one poster per (author, unpinned work):
--        { author, work, author_pin_count, teaser_quote }
--      teaser_quote is deterministic: the text of the quote with the lowest id in
--      that work. It is NULL if the work has no quotes in the corpus.
--
-- Query:
--
-- SELECT ap.author                                   AS author,
--        wp.work                                     AS work,
--        ap.pin_count                                AS author_pin_count,
--        (SELECT q.text
--           FROM quotes q
--          WHERE q.work_id = wp.work_id
--          ORDER BY q.id
--          LIMIT 1)                                  AS teaser_quote
--   FROM v_author_pin_counts ap
--   JOIN v_work_pin_counts  wp ON wp.author_id = ap.author_id
--  WHERE ap.pin_count >= 1
--    AND wp.pin_count  = 0
--  ORDER BY ap.pin_count DESC, ap.author ASC, wp.work ASC;
