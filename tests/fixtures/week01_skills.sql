-- schema-version: 0003
-- A character with skill XP, exactly as character_skills (migration 0003) stores it.
-- Used by tests/unit/test_gameplay_skills.gd and qa's save-compat test. Includes a skill at
-- 0 XP and a skill id the game doesn't know (as if it were retired later): both must load
-- without being lost. The character also carries a small pack (migration 0002).
-- Password is "oldpassword" hashed with 1000 iterations.
INSERT INTO accounts (username, username_lc, password_hash)
VALUES ('Grove_Feller', 'grove_feller', 'pbkdf2_sha256$1000$Gyxw0pfiVBuoTOa/ZpG1Fg==$MV7WPZNjd3gKSpCZmKJrVdu8XL9WVVedP4eFFM76848=')
ON CONFLICT (username_lc) DO NOTHING;

INSERT INTO characters (account_id, name, pos_x, pos_y, pos_z, yaw, appearance_seed)
SELECT a.id, 'Grove_Feller', 6.0, 0, -4.0, 1.0, 9876
FROM accounts a
WHERE a.username_lc = 'grove_feller'
  AND NOT EXISTS (SELECT 1 FROM characters c WHERE c.account_id = a.id);

INSERT INTO inventory_items (character_id, item, qty)
SELECT c.id, v.item, v.qty
FROM characters c
JOIN accounts a ON a.id = c.account_id
CROSS JOIN (VALUES ('pine_wood', 5), ('stone_axe', 1)) AS v(item, qty)
WHERE a.username_lc = 'grove_feller'
ON CONFLICT (character_id, item) DO NOTHING;

INSERT INTO character_skills (character_id, skill, xp)
SELECT c.id, v.skill, v.xp
FROM characters c
JOIN accounts a ON a.id = c.account_id
CROSS JOIN (VALUES ('felling', 1700), ('quarrying', 140), ('tapping', 0), ('old_lore', 55)) AS v(skill, xp)
WHERE a.username_lc = 'grove_feller'
ON CONFLICT (character_id, skill) DO NOTHING;
