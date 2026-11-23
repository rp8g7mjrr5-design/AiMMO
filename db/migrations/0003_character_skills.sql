-- Milestone 1: skills and XP. One row per (character, skill id), holding the total XP.
-- Rule: migrations are add-only. Never DROP or RENAME anything that holds player data.
-- Levels are not stored: game/shared/skills.gd turns XP into a level, so the curve can be
-- retuned without touching anyone's XP. The server never deletes or lowers these rows.
-- Characters saved before this migration simply have no rows: level 1 in every skill.

CREATE TABLE IF NOT EXISTS character_skills (
    character_id  BIGINT      NOT NULL REFERENCES characters(id),
    skill         TEXT        NOT NULL,
    xp            BIGINT      NOT NULL DEFAULT 0 CHECK (xp >= 0),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, skill)
);
