-- Week 00: what each character carries. One row per (character, item id).
-- Rule: migrations are add-only. Never DROP or RENAME anything that holds player data.
-- A used-up item keeps its row with qty = 0 (the server never deletes inventory rows).
-- Characters saved before this migration simply have no rows: an empty pack.

CREATE TABLE IF NOT EXISTS inventory_items (
    character_id  BIGINT      NOT NULL REFERENCES characters(id),
    item          TEXT        NOT NULL,
    qty           INTEGER     NOT NULL DEFAULT 0 CHECK (qty >= 0),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, item)
);
