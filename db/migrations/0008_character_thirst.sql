-- Thirst, the second survival need (game/shared/needs.gd; the owner's survival plan, step 3).
-- Rule: migrations are add-only. Never DROP or RENAME anything that holds player data.
-- 0 is parched, 100 is quenched. Every character saved before this migration gets 100, so
-- nobody logs in thirsty after the update.

ALTER TABLE characters ADD COLUMN IF NOT EXISTS thirst REAL NOT NULL DEFAULT 100;
