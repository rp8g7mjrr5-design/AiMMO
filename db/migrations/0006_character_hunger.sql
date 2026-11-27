-- Hunger, the first survival need (game/shared/needs.gd; the owner's survival plan, 2026-11-27).
-- Rule: migrations are add-only. Never DROP or RENAME anything that holds player data.
-- 0 is starving, 100 is full. Every character saved before this migration gets 100, so
-- nobody logs in hungry after the update.

ALTER TABLE characters ADD COLUMN IF NOT EXISTS hunger REAL NOT NULL DEFAULT 100;
