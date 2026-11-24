-- Character customization: the look a player chose in the character-creation window.
-- Rule: migrations are add-only. Never DROP or RENAME anything that holds player data.
-- Stored as the JSON text of an Appearance look (game/shared/appearance.gd), e.g.
-- {"body":1,"height":2,...}. '' means "not chosen yet": the character is drawn from its
-- appearance_seed exactly as before, and the creation window opens at their next login.
-- Every character saved before this migration gets '' and so keeps the look it had.

ALTER TABLE characters ADD COLUMN IF NOT EXISTS appearance TEXT NOT NULL DEFAULT '';
