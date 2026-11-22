-- schema-version: 0002
-- A character with a pack, exactly as inventory_items (migration 0002) stores it.
-- Used by tests/unit/test_gameplay_inventory.gd and qa's save-compat test. Includes a used-up item (qty 0) and an item id
-- the game doesn't know (as if it were retired later): both must load without being lost.
-- Password is "oldpassword" hashed with 1000 iterations.
INSERT INTO accounts (username, username_lc, password_hash)
VALUES ('Pack_Carrier', 'pack_carrier', 'pbkdf2_sha256$1000$Gyxw0pfiVBuoTOa/ZpG1Fg==$MV7WPZNjd3gKSpCZmKJrVdu8XL9WVVedP4eFFM76848=')
ON CONFLICT (username_lc) DO NOTHING;

INSERT INTO characters (account_id, name, pos_x, pos_y, pos_z, yaw, appearance_seed)
SELECT a.id, 'Pack_Carrier', -30.0, 0, 12.5, 0.5, 4321
FROM accounts a
WHERE a.username_lc = 'pack_carrier'
  AND NOT EXISTS (SELECT 1 FROM characters c WHERE c.account_id = a.id);

INSERT INTO inventory_items (character_id, item, qty)
SELECT c.id, v.item, v.qty
FROM characters c
JOIN accounts a ON a.id = c.account_id
CROSS JOIN (VALUES ('ash_wood', 7), ('stone', 0), ('ember_sap', 2), ('retired_relic', 1)) AS v(item, qty)
WHERE a.username_lc = 'pack_carrier'
ON CONFLICT (character_id, item) DO NOTHING;
