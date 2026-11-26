-- Monthly wipes (owner, 2026-11-26): a server with AIMMO_WIPE=monthly rolls a new island
-- each month. Rule: migrations are add-only. Never DROP or RENAME anything that holds player data.
--
-- worlds: every world this server has run, oldest first, kept forever. The newest row is the
-- one running now; wipes_at is when it ends (Unix seconds, UTC), wiped_at when it did.
-- characters.world_id: the world a character was last on. 0 means "before wipes": a server
-- that doesn't wipe never reads it.
-- wipe_archive: what a character had on a world when they first came back after its wipe
-- (position and pack as JSON text). The pack is then emptied (qty 0, rows kept); look,
-- name and everything else are untouched.

CREATE TABLE IF NOT EXISTS worlds (
    id           BIGSERIAL PRIMARY KEY,
    seed         BIGINT      NOT NULL,
    gen_version  INTEGER     NOT NULL,
    size_m       DOUBLE PRECISION NOT NULL,
    started_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    wipes_at     BIGINT      NOT NULL DEFAULT 0,
    wiped_at     TIMESTAMPTZ
);

ALTER TABLE characters ADD COLUMN IF NOT EXISTS world_id BIGINT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS wipe_archive (
    id            BIGSERIAL PRIMARY KEY,
    character_id  BIGINT      NOT NULL REFERENCES characters(id),
    world_id      BIGINT      NOT NULL,
    pos_x         DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_y         DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_z         DOUBLE PRECISION NOT NULL DEFAULT 0,
    inventory     TEXT        NOT NULL DEFAULT '{}',
    archived_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS wipe_archive_character_idx ON wipe_archive (character_id);
