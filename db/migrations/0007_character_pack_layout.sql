-- The grid pack (game/shared/pack_grid.gd; owner direction 2026-11-27, an inventory that
-- works like Tarkov or ARC Raiders). Rule: migrations are add-only. Never DROP or RENAME
-- anything that holds player data.
-- Where each stack sits, as the JSON text of PackGrid places: [["ash_wood",0,0,0,false],...].
-- The counts stay in inventory_items; this is only the arrangement. '' means "not laid out
-- yet": every character saved before this migration is packed top-left first at its next
-- login, and keeps everything it owns.

ALTER TABLE characters ADD COLUMN IF NOT EXISTS pack_layout TEXT NOT NULL DEFAULT '';
