-- A character exactly as Week 00 stores it. Used by tests/unit/test_qa_save_compat.gd.
-- Password is "oldpassword" hashed with 1000 iterations.
INSERT INTO accounts (username, username_lc, password_hash)
VALUES ('Legacy_Wanderer', 'legacy_wanderer', 'pbkdf2_sha256$1000$Gyxw0pfiVBuoTOa/ZpG1Fg==$MV7WPZNjd3gKSpCZmKJrVdu8XL9WVVedP4eFFM76848=')
ON CONFLICT (username_lc) DO NOTHING;

INSERT INTO characters (account_id, name, pos_x, pos_y, pos_z, yaw, appearance_seed)
SELECT a.id, 'Legacy_Wanderer', 42.5, 0, -17.25, 1.0, 1234
FROM accounts a
WHERE a.username_lc = 'legacy_wanderer'
  AND NOT EXISTS (SELECT 1 FROM characters c WHERE c.account_id = a.id);
